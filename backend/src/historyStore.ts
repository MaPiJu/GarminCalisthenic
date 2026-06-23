import { promises as fs } from "node:fs";
import path from "node:path";
import { z } from "zod/v4";
import { SetResultSchema, type SetResult, type LogPayload } from "./sessionSchema";

// ---------------------------------------------------------------------------
// Durable logged-history store (Phase C). Mirrors sessionStore: an in-memory
// map of per-athlete workout results, backed by a JSON file (atomic, serialized
// writes). The generator reads the recent history to adapt the next session;
// the POST /v1/sessions/log endpoint appends to it. Bounded per athlete so the
// file (and the prompt it feeds) stays small.
// ---------------------------------------------------------------------------

export interface LoggedSession {
  date: string; // YYYY-MM-DD the results were recorded
  session_id: string; // the session these results belong to
  results: SetResult[];
}

const STORE_PATH = process.env.HISTORY_DB_PATH
  ? path.resolve(process.env.HISTORY_DB_PATH)
  : path.join(process.cwd(), "data", "history.json");

const MAX_PER_USER = 30; // keep only recent sessions — that's what adaptation needs

const LoggedSessionSchema = z.object({
  date: z.string(),
  session_id: z.string(),
  results: z.array(SetResultSchema),
});

const history = new Map<string, LoggedSession[]>();
let loadPromise: Promise<void> | null = null;

function load(): Promise<void> {
  if (loadPromise) return loadPromise;
  loadPromise = (async () => {
    try {
      const raw = await fs.readFile(STORE_PATH, "utf8");
      const parsed = JSON.parse(raw) as Record<string, unknown>;
      for (const [userId, value] of Object.entries(parsed)) {
        const result = z.array(LoggedSessionSchema).safeParse(value);
        if (result.success) {
          history.set(userId, result.data);
        } else {
          console.warn(`[historyStore] dropping invalid history for "${userId}"`);
        }
      }
    } catch (err: unknown) {
      if ((err as NodeJS.ErrnoException).code !== "ENOENT") {
        console.warn("[historyStore] could not read store, starting empty:", err);
      }
    }
  })();
  return loadPromise;
}

export async function getHistory(userId: string): Promise<LoggedSession[]> {
  await load();
  return history.get(userId) ?? [];
}

export async function appendLog(userId: string, payload: LogPayload): Promise<void> {
  await load();
  const entry: LoggedSession = {
    date: new Date().toISOString().slice(0, 10),
    session_id: payload.session_id,
    results: payload.results,
  };
  // Re-logging the same session replaces the prior entry instead of duplicating.
  const list = (history.get(userId) ?? []).filter((e) => e.session_id !== payload.session_id);
  list.push(entry);
  history.set(userId, list.slice(-MAX_PER_USER));
  await persist();
}

// Serialize disk writes so concurrent logs never interleave (see sessionStore).
let writeChain: Promise<void> = Promise.resolve();
function persist(): Promise<void> {
  writeChain = writeChain.then(async () => {
    const snapshot = JSON.stringify(Object.fromEntries(history), null, 2);
    await fs.mkdir(path.dirname(STORE_PATH), { recursive: true });
    const tmp = `${STORE_PATH}.${process.pid}.tmp`;
    await fs.writeFile(tmp, snapshot);
    await fs.rename(tmp, STORE_PATH); // atomic replace
  });
  return writeChain;
}
