import "dotenv/config";
import express, { type NextFunction, type Request, type Response } from "express";
import { generateSession } from "./generateSession";

// ---------------------------------------------------------------------------
// HTTP surface. ONE endpoint the watch calls once, before a workout:
//   GET /v1/sessions/today?user_id=<id>   (Authorization: Bearer <token>)
//
// The path mirrors the watch's ApiConfig: BASE_URL ends in /v1 and
// sessionUrl() appends "/sessions/today". Point ApiConfig.BASE_URL at
// http://<host>:<PORT>/v1 for the simulator (HTTPS required on a real device).
// ---------------------------------------------------------------------------

const PORT = Number(process.env.PORT ?? 8080);
const AUTH_TOKEN = process.env.API_AUTH_TOKEN ?? "DEV_TOKEN";

const app = express();

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

app.listen(PORT, () => {
  const mode = process.env.ANTHROPIC_API_KEY ? "Claude generation" : "sample (no ANTHROPIC_API_KEY)";
  console.log(`coach backend listening on http://localhost:${PORT}  [${mode}]`);
  console.log(`  GET http://localhost:${PORT}/v1/sessions/today?user_id=demo-user`);
});
