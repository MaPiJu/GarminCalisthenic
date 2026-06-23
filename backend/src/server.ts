import "dotenv/config";
import express, { type NextFunction, type Request, type Response } from "express";
import { generateSession } from "./generateSession";
import { coachChat } from "./coach";
import { appendLog } from "./historyStore";
import { getSession, putSession } from "./sessionStore";
import { appendRecentChange, getRecentChanges } from "./coachStore";
import {
  ChatPayloadSchema,
  ConfirmPayloadSchema,
  LogPayloadSchema,
  sessionIdFor,
} from "./sessionSchema";

// ---------------------------------------------------------------------------
// HTTP surface.
//
// The watch calls:
//   GET  /v1/sessions/today?user_id=<id>   before a workout (fetch the plan)
//   POST /v1/sessions/log                  after a workout (report what was done)
//
// The mobile companion (coach-IA) calls — propose → confirm, server is the hub:
//   POST /v1/coach/chat                    chat with the coach, get a proposal
//   POST /v1/sessions/confirm              accept a session → becomes today's
//   GET  /v1/program?user_id=<id>          read today's session + recent changes
//
// All require Authorization: Bearer <token>. The GET path mirrors the watch's
// ApiConfig (BASE_URL ends in /v1 + sessionUrl() appends "/sessions/today").
// Point ApiConfig.BASE_URL at http://<host>:<PORT>/v1 for the simulator
// (HTTPS required on a real device).
// ---------------------------------------------------------------------------

const PORT = Number(process.env.PORT ?? 8080);
const AUTH_TOKEN = process.env.API_AUTH_TOKEN ?? "DEV_TOKEN";

const app = express();
app.use(express.json());

// Bearer-token gate. Matches the watch's ApiConfig.authToken() (dev default
// "DEV_TOKEN"), so it works out of the box and is trivially swapped in prod.
function requireBearer(req: Request, res: Response, next: NextFunction): void {
  const header = req.get("authorization") ?? "";
  const token = header.startsWith("Bearer ") ? header.slice(7) : null;
  if (token !== AUTH_TOKEN) {
    res.status(401).json({ error: "unauthorized" });
    return;
  }
  next();
}

app.get("/health", (_req, res) => {
  res.json({ ok: true });
});

app.get("/v1/sessions/today", requireBearer, async (req: Request, res: Response) => {
  const userId = (req.query.user_id as string | undefined) ?? "demo-user";
  try {
    const session = await generateSession(userId);
    res.json(session);
  } catch (err) {
    console.error("[GET /v1/sessions/today] failed:", err);
    res.status(500).json({ error: "generation_failed" });
  }
});

// Phase C: the watch reports completed sets here after a workout. Stored per
// athlete and fed back into the next session's generation. Additive — the watch
// can adopt it whenever; generation works fine without any logged history.
app.post("/v1/sessions/log", requireBearer, async (req: Request, res: Response) => {
  const parsed = LogPayloadSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: "invalid_payload" });
    return;
  }
  try {
    await appendLog(parsed.data.user_id, parsed.data);
    res.json({ ok: true });
  } catch (err) {
    console.error("[POST /v1/sessions/log] failed:", err);
    res.status(500).json({ error: "log_failed" });
  }
});

// ---------------------------------------------------------------------------
// Mobile ↔ server (coach-IA companion). Propose → confirm: the coach proposes a
// session in chat, the athlete confirms it, and only then does it become "today's
// session" that the watch pulls. The phone talks only to the server.
// ---------------------------------------------------------------------------

// Talk to the coach. Returns the coach's reply and, once it has enough to go on,
// an attached proposed_session (null while still gathering info).
app.post("/v1/coach/chat", requireBearer, async (req: Request, res: Response) => {
  const parsed = ChatPayloadSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: "invalid_payload" });
    return;
  }
  try {
    const { reply, proposed_session } = await coachChat(parsed.data.user_id, parsed.data.message);
    res.json({ reply, proposed_session });
  } catch (err) {
    console.error("[POST /v1/coach/chat] failed:", err);
    res.status(500).json({ error: "chat_failed" });
  }
});

// Confirm a session the athlete accepted. Stored under the athlete+day key so
// GET /v1/sessions/today serves it to the watch, and recorded as a recent change.
app.post("/v1/sessions/confirm", requireBearer, async (req: Request, res: Response) => {
  const parsed = ConfirmPayloadSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: "invalid_payload" });
    return;
  }
  try {
    const { user_id, session } = parsed.data;
    const key = sessionIdFor(user_id);
    // The server owns the id: stamp the deterministic athlete+day key so the
    // watch's local log key and offline cache stay stable for the day.
    const confirmed = { ...session, session_id: key };
    await putSession(key, confirmed);
    await appendRecentChange(user_id, `Confirmed "${confirmed.session_name}" for ${key.slice(-10)}`);
    res.json({ ok: true });
  } catch (err) {
    console.error("[POST /v1/sessions/confirm] failed:", err);
    res.status(500).json({ error: "confirm_failed" });
  }
});

// Read the current program: today's stored session (null if none yet) plus the
// recent human-readable adaptation notes.
app.get("/v1/program", requireBearer, async (req: Request, res: Response) => {
  const userId = (req.query.user_id as string | undefined) ?? "demo-user";
  try {
    const today = await getSession(sessionIdFor(userId));
    const recent_changes = await getRecentChanges(userId);
    res.json({ today, recent_changes });
  } catch (err) {
    console.error("[GET /v1/program] failed:", err);
    res.status(500).json({ error: "program_failed" });
  }
});

app.listen(PORT, () => {
  const mode = process.env.ANTHROPIC_API_KEY ? "Claude generation" : "sample (no ANTHROPIC_API_KEY)";
  console.log(`coach backend listening on http://localhost:${PORT}  [${mode}]`);
  console.log(`  GET  http://localhost:${PORT}/v1/sessions/today?user_id=demo-user`);
  console.log(`  POST http://localhost:${PORT}/v1/sessions/log`);
  console.log(`  POST http://localhost:${PORT}/v1/coach/chat`);
  console.log(`  POST http://localhost:${PORT}/v1/sessions/confirm`);
  console.log(`  GET  http://localhost:${PORT}/v1/program?user_id=demo-user`);
});
