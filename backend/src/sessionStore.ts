import { promises as fs } from "node:fs";
import path from "node:path";
import { SessionSchema, type Session } from "./sessionSchema";

// ---------------------------------------------------------------------------
// Durable session store (Phase A, Step 2).
//
// Replaces the old in-memory Map: a generated session is now keyed by
// `<user_id>-<YYYY-MM-DD>` and written to a JSON file, so "today's session"
// survives a server restart and stays stable for the whole day. That is the
// prerequisite for the day-to-day adaptation loop and keeps the watch's 8 s
// budget safe — a stored session is served instantly instead of regenerated.
//
// Design: an in-memory Map mirrors the file (instant reads); every write
// updates the Map and atomically rewrites the file (temp file + rename), with
// writes serialized so concurrent puts can't clobber each other. JSON keeps the
// "start simple" promise of the roadmap — no native deps, easy to inspect.
// ---------------------------------------------------------------------------

const STORE_PATH = process.env.SESSIONS_DB_PATH
  ? path.resolve(process.env.SESSIONS_DB_PATH)
  : path.join(process.cwd(), "data", "sessions.json");

const sessions = new Map<string, Session>();
let loadPromise: Promise<void> | null = null;

// Load the file once, lazily. Anything that doesn't validate against the
// contract is dropped rather than served — the store only ever hands back
// well-formed sessions.
function load(): Promise<void> {
  if (loadPromise) return loadPromise;
  loadPromise = (async () => {
    try {
      const raw = await fs.readFile(STORE_PATH, "utf8");
      const parsed = JSON.parse(raw) as Record<string, unknown>;
      for (const [key, value] of Object.entries(parsed)) {
        const result = SessionSchema.safeParse(value);
        if (result.success) {
          sessions.set(key, result.data);
        } else {
          console.warn(`[sessionStore] dropping invalid stored session for "${key}"`);
        }
      }
    } catch (err: unknown) {
      if ((err as NodeJS.ErrnoException).code !== "ENOENT") {
        console.warn("[sessionStore] could not read store, starting empty:", err);
      }
    }
  })();
  return loadPromise;
}

export async function getSession(key: string): Promise<Session | null> {
  await load();
  return sessions.get(key) ?? null;
}

export async function putSession(key: string, session: Session): Promise<void> {
  await load();
  sessions.set(key, session);
  await persist();
}

// Serialize disk writes: each persist() chains onto the previous one so
// concurrent requests never interleave writes to the same file.
let writeChain: Promise<void> = Promise.resolve();
function persist(): Promise<void> {
  writeChain = writeChain.then(async () => {
    const snapshot = JSON.stringify(Object.fromEntries(sessions), null, 2);
    await fs.mkdir(path.dirname(STORE_PATH), { recursive: true });
    const tmp = `${STORE_PATH}.${process.pid}.tmp`;
    await fs.writeFile(tmp, snapshot);
    await fs.rename(tmp, STORE_PATH); // atomic replace
  });
  return writeChain;
}
