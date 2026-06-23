import Anthropic from "@anthropic-ai/sdk";
import { zodOutputFormat } from "@anthropic-ai/sdk/helpers/zod";
import { z } from "zod/v4";
import { SessionSchema, sampleSession, sessionIdFor, type Session } from "./sessionSchema";
import { recentHistorySummary } from "./generateSession";
import { appendCoachMessages, getCoachState, type CoachMessage } from "./coachStore";

// ---------------------------------------------------------------------------
// The coach-IA chat (mobile companion). The athlete chats with the coach; once
// it has enough to be useful it attaches a `proposed_session` (the exact watch
// contract shape). The flow is propose → confirm: nothing reaches the watch
// until the athlete validates it via POST /sessions/confirm.
//
// Same discipline as generateSession: structured outputs make Claude's reply
// validate, and if there's no API key (or generation fails) we fall back to a
// canned reply + the sample session so the flow is fully testable offline.
// ---------------------------------------------------------------------------

const client = process.env.ANTHROPIC_API_KEY ? new Anthropic() : null;

// One structured object carries BOTH the conversational reply and the optional
// attached proposal — so a single Claude call yields the whole guichet response.
export const CoachReplySchema = z.object({
  reply: z.string(),
  proposed_session: SessionSchema.nullable(),
});
export type CoachReply = z.infer<typeof CoachReplySchema>;

const SYSTEM_PROMPT = [
  "You are a friendly, expert calisthenics coach chatting with an athlete in a",
  "mobile app. Hold a natural conversation: ask about their goals, experience,",
  "available time, equipment and any injuries, and how recent sessions felt.",
  "As soon as you have enough to be useful, PROPOSE a concrete session for today.",
  "",
  "Output (structured) rules:",
  '- "reply": your conversational message to the athlete — warm, concise, plain',
  "  text (no markdown).",
  '- "proposed_session": a full session object once you can propose one; null',
  "  while you are still gathering information. Do not invent details the athlete",
  "  has not given — ask first, then propose.",
  "",
  "When you do propose, the session must satisfy the watch contract:",
  "- 2 to 4 blocks (e.g. Warm-up, Push, Pull, Core, Cool-down), each 1-4 exercises.",
  "- Bodyweight calisthenics only — no equipment beyond a pull-up bar.",
  "- Reps exercise: target_reps a positive integer, target_hold_seconds = null.",
  "  Use target_reps = null only to mean 'to failure'.",
  "- Isometric hold (plank, hollow hold, L-sit, wall sit, dead hang):",
  "  target_hold_seconds a positive integer, target_reps = null.",
  "- rest_seconds is the rest after each set (0-180), realistic for the effort.",
  "- session_id will be overwritten by the server; put any non-empty string.",
  "- session_name: a short, motivating title.",
  "- If recent performance is provided, ADAPT: progress movements whose targets",
  "  were met, hold or regress those that were missed.",
].join("\n");

// Serialize chats per athlete so concurrent messages can't interleave the
// conversation's read-modify-write (mirrors the in-flight discipline of
// generateSession, but ordered rather than deduped — each message is distinct).
const chains = new Map<string, Promise<CoachReply>>();

export async function coachChat(userId: string, message: string): Promise<CoachReply> {
  const prior = chains.get(userId) ?? Promise.resolve<CoachReply | null>(null);
  const next = prior.catch(() => null).then(() => runChat(userId, message));
  chains.set(userId, next);
  try {
    return await next;
  } finally {
    if (chains.get(userId) === next) {
      chains.delete(userId);
    }
  }
}

async function runChat(userId: string, message: string): Promise<CoachReply> {
  const state = await getCoachState(userId);

  let reply: CoachReply;
  if (client == null) {
    reply = fallbackReply(userId);
  } else {
    try {
      reply = await callCoach(userId, state.messages, message);
    } catch (err) {
      console.warn("[coachChat] generation failed, serving sample proposal:", err);
      reply = fallbackReply(userId);
    }
  }

  // The server owns the id; stamp the deterministic athlete+day id so a later
  // confirm (and the watch's cache key) stays stable for the day.
  if (reply.proposed_session) {
    reply.proposed_session.session_id = sessionIdFor(userId);
  }

  await appendCoachMessages(userId, [
    { role: "user", content: message },
    { role: "assistant", content: reply.reply },
  ]);

  return reply;
}

async function callCoach(userId: string, prior: CoachMessage[], message: string): Promise<CoachReply> {
  const history = await recentHistorySummary(userId);
  const system = history
    ? `${SYSTEM_PROMPT}\n\nThe athlete's recent performance (adapt accordingly):\n${history}`
    : SYSTEM_PROMPT;

  const messages = [
    ...prior.map((m) => ({ role: m.role, content: m.content })),
    { role: "user" as const, content: message },
  ];

  const response = await client!.messages.parse({
    model: "claude-haiku-4-5",
    max_tokens: 4096,
    system,
    output_config: { format: zodOutputFormat(CoachReplySchema) },
    messages,
  });

  if (response.stop_reason === "refusal" || response.parsed_output == null) {
    throw new Error(`no usable output (stop_reason=${response.stop_reason})`);
  }
  return response.parsed_output;
}

// Offline / no-key fallback: a canned reply plus the sample session as the
// proposal, so propose → confirm → GET /sessions/today works end-to-end without
// an API key (same spirit as generateSession serving the sample).
function fallbackReply(userId: string): CoachReply {
  const session: Session = sampleSession(userId);
  session.session_id = sessionIdFor(userId);
  return {
    reply:
      "Here's a balanced full-body session to get you started — confirm it when " +
      "you're ready and it'll be waiting on your watch. Tell me your goals or how " +
      "it felt and I'll tailor the next one. (Coach AI is in offline sample mode; " +
      "set ANTHROPIC_API_KEY for fully tailored coaching.)",
    proposed_session: session,
  };
}
