import Anthropic from "@anthropic-ai/sdk";
import { zodOutputFormat } from "@anthropic-ai/sdk/helpers/zod";
import { SessionSchema, sampleSession, sessionIdFor, type Session } from "./sessionSchema";
import { getSession, putSession } from "./sessionStore";

// ---------------------------------------------------------------------------
// The "coach IA": asks Claude to generate today's calisthenics session and
// returns it as the JSON contract. Structured outputs (zodOutputFormat) make
// the model's response validate against SessionSchema, so the watch always
// receives a well-formed plan.
//
// If no API key is configured, or generation fails for any reason, we fall back
// to a built-in sample — the endpoint must never leave the watch without a plan.
// ---------------------------------------------------------------------------

const client = process.env.ANTHROPIC_API_KEY ? new Anthropic() : null;

const SYSTEM_PROMPT = [
  "You are a calisthenics coach. Generate ONE training session for the day,",
  "as structured data only.",
  "",
  "Rules:",
  "- 2 to 4 blocks (e.g. Warm-up, Push, Pull, Core, Cool-down), each with 1-4 exercises.",
  "- Bodyweight calisthenics movements only — no equipment beyond a pull-up bar.",
  "- For a reps exercise: set target_reps (a positive integer) and target_hold_seconds = null.",
  "  Use target_reps = null only to mean 'to failure'.",
  "- For an isometric hold (plank, hollow hold, L-sit, wall sit, dead hang):",
  "  set target_hold_seconds (a positive integer) and target_reps = null.",
  "- rest_seconds is the rest after each set (0-180), realistic for the effort.",
  "- session_id will be overwritten by the server; put any non-empty string.",
  "- Give session_name a short, motivating title.",
].join("\n");

// Dedup concurrent generations for the same athlete+day: two near-simultaneous
// GETs share a single in-flight promise instead of each calling Claude (which
// costs money/latency and races on the store). Persistence itself lives in
// sessionStore — a stored session survives restarts and stays stable all day.
const inFlight = new Map<string, Promise<Session>>();

export async function generateSession(userId: string): Promise<Session> {
  const key = sessionIdFor(userId);

  const stored = await getSession(key);
  if (stored) {
    return stored;
  }

  const pending = inFlight.get(key);
  if (pending) {
    return pending;
  }

  const promise = produceSession(userId, key);
  inFlight.set(key, promise);
  try {
    return await promise;
  } finally {
    inFlight.delete(key);
  }
}

async function produceSession(userId: string, key: string): Promise<Session> {
  // No key configured: the sample IS the intended product, so persist it —
  // it's deterministic and should stay stable for the day.
  if (client == null) {
    const session = sampleSession(userId);
    session.session_id = key; // server owns the id, regardless of the source
    await putSession(key, session);
    return session;
  }

  // Key present: try real generation and persist the result. On a transient
  // failure, serve the sample but DON'T persist it — the next request retries
  // real generation instead of being locked into a degraded plan for the day.
  try {
    const session = await callClaude(userId);
    session.session_id = key;
    await putSession(key, session);
    return session;
  } catch (err) {
    console.warn("[generateSession] generation failed, serving sample (not persisted):", err);
    const fallback = sampleSession(userId);
    fallback.session_id = key;
    return fallback;
  }
}

async function callClaude(userId: string): Promise<Session> {
  const response = await client!.messages.parse({
    model: "claude-haiku-4-5",
    max_tokens: 4096,
    system: SYSTEM_PROMPT,
    output_config: { format: zodOutputFormat(SessionSchema) },
    messages: [
      {
        role: "user",
        content: `Generate today's calisthenics session for athlete "${userId}".`,
      },
    ],
  });

  if (response.stop_reason === "refusal" || response.parsed_output == null) {
    throw new Error(`no usable output (stop_reason=${response.stop_reason})`);
  }
  return response.parsed_output;
}
