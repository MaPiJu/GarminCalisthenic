import { promises as fs } from "node:fs";
import path from "node:path";
import { z } from "zod/v4";

// ---------------------------------------------------------------------------
// Durable coach-IA store (mobile companion). Mirrors sessionStore/historyStore:
// an in-memory map keyed by user_id, backed by a JSON file with atomic,
// serialized writes. Holds two things per athlete:
//   - messages:        the running coach conversation (so /coach/chat is
//                      stateful — Claude sees the prior turns), bounded.
//   - recent_changes:  human-readable adaptation notes surfaced by GET /program
//                      (e.g. "Confirmed 'Push & Core' for 2026-06-23"), bounded.
// Both are bounded so the file (and the prompt the conversation feeds) stays
// small. "Start simple": plain JSON, no native deps, easy to inspect.
// ---------------------------------------------------------------------------

export interface CoachMessage {
  role: "user" | "assistant";
  content: string;
}

export interface CoachState {
  messages: CoachMessage[];
  recent_changes: string[];
}

const STORE_PATH = process.env.COACH_DB_PATH
  ? path.resolve(process.env.COACH_DB_PATH)
  : path.join(process.cwd(), "data", "coach.json");

const MAX_MESSAGES = 40; // keep recent turns — enough context, small prompt/file
const MAX_CHANGES = 20; // keep recent adaptation notes for GET /program

const CoachMessageSchema = z.object({
  role: z.enum(["user", "assistant"]),
  content: z.string(),
});

const CoachStateSchema = z.object({
  messages: z.array(CoachMessageSchema),
  recent_changes: z.array(z.string()),
});

const states = new Map<string, CoachState>();
let loadPromise: Promise<void> | null = null;

function load(): Promise<void> {
  if (loadPromise) return loadPromise;
  loadPromise = (async () => {
    try {
      const raw = await fs.readFile(STORE_PATH, "utf8");
      const parsed = JSON.parse(raw) as Record<string, unknown>;
      for (const [userId, value] of Object.entries(parsed)) {
        const result = CoachStateSchema.safeParse(value);
        if (result.success) {
          states.set(userId, result.data);
        } else {
          console.warn(`[coachStore] dropping invalid state for "${userId}"`);
        }
      }
    } catch (err: unknown) {
      if ((err as NodeJS.ErrnoException).code !== "ENOENT") {
        console.warn("[coachStore] could not read store, starting empty:", err);
      }
    }
  })();
  return loadPromise;
}

function emptyState(): CoachState {
  return { messages: [], recent_changes: [] };
}

export async function getCoachState(userId: string): Promise<CoachState> {
  await load();
  return states.get(userId) ?? emptyState();
}

// Append a completed conversation turn (the user message + the coach reply).
export async function appendCoachMessages(userId: string, messages: CoachMessage[]): Promise<void> {
  await load();
  const state = states.get(userId) ?? emptyState();
  state.messages = [...state.messages, ...messages].slice(-MAX_MESSAGES);
  states.set(userId, state);
  await persist();
}

// Record a human-readable adaptation note (surfaced by GET /program).
export async function appendRecentChange(userId: string, note: string): Promise<void> {
  await load();
  const state = states.get(userId) ?? emptyState();
  state.recent_changes = [...state.recent_changes, note].slice(-MAX_CHANGES);
  states.set(userId, state);
  await persist();
}

export async function getRecentChanges(userId: string): Promise<string[]> {
  const state = await getCoachState(userId);
  return state.recent_changes;
}

// Serialize disk writes so concurrent calls never interleave (see sessionStore).
let writeChain: Promise<void> = Promise.resolve();
function persist(): Promise<void> {
  writeChain = writeChain.then(async () => {
    const snapshot = JSON.stringify(Object.fromEntries(states), null, 2);
    await fs.mkdir(path.dirname(STORE_PATH), { recursive: true });
    const tmp = `${STORE_PATH}.${process.pid}.tmp`;
    await fs.writeFile(tmp, snapshot);
    await fs.rename(tmp, STORE_PATH); // atomic replace
  });
  return writeChain;
}
