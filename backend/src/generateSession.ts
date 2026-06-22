import Anthropic from "@anthropic-ai/sdk";
import { zodOutputFormat } from "@anthropic-ai/sdk/helpers/zod";
import { SessionSchema, sampleSession, sessionIdFor, type Session } from "./sessionSchema";

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

// In-memory cache keyed by athlete + day, so repeated GETs are instant and the
// watch's short request budget isn't spent regenerating an identical plan.
const cache = new Map<string, Session>();

export async function generateSession(userId: string): Promise<Session> {
  const key = sessionIdFor(userId);
  const cached = cache.get(key);
  if (cached) {
    return cached;
  }

  let session: Session;
  if (client == null) {
    session = sampleSession(userId);
  } else {
    try {
      session = await callClaude(userId);
    } catch (err) {
      console.warn("[generateSession] generation failed, serving sample:", err);
      session = sampleSession(userId);
    }
  }

  // Server owns the id so it's deterministic regardless of what the model wrote.
  session.session_id = key;
  cache.set(key, session);
  return session;
}

async function callClaude(userId: string): Promise<Session> {
  const response = await client!.messages.parse({
    model: "claude-opus-4-8",
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
