# CLAUDE.md — GarminCalisthenic monorepo

Top-level project memory. Each **brick** keeps its own detailed `CLAUDE.md`;
this file is just the map and the one thing both bricks must agree on.

> **Read [`ARCHITECTURE.md`](ARCHITECTURE.md) first for cross-brick design** — the
> hub model and how the mobile app, server, and watch interact (decision: the
> watch pulls from the server; clients never talk to each other directly).

## Layout

```
/                  ← monorepo root (this file, shared contract, .gitignore)
├── watch/         ← Connect IQ on-watch app (Monkey C). The runtime brick.
│                    Build/open this folder as the project root in the
│                    Monkey C VS Code extension; monkey.jungle uses default
│                    discovery relative to its own location, so nothing in the
│                    build changed by moving it here. See watch/CLAUDE.md.
└── backend/       ← Server brick: a Node/TypeScript service that calls the
                     Claude API to generate a session and returns the contract
                     JSON. Minimal but runnable. See backend/README.md.
```

## Bricks

- **watch/** — the on-watch calisthenics coach. Loads the day's session, walks
  the user through each set, runs rest/hold timers, validates and logs every set
  **locally and immediately**. Fully working today; full details, target devices,
  architecture and current state live in **`watch/CLAUDE.md`**.
- **backend/** — the "coach IA" service (Node/TS, Express + Anthropic SDK). One
  endpoint, `GET /v1/sessions/today`, generates a session with Claude
  (`claude-haiku-4-5`, structured outputs) and returns the JSON contract below;
  serves a built-in sample when no `ANTHROPIC_API_KEY` is set. The watch speaks to
  it through `watch/source/data/ApiConfig.mc` (endpoint, auth, timeout) +
  `SessionRepository.fetchSession()` (one grouped request, offline fallback).

## Shared contract (source of truth)

This is the **only** interface between the two bricks — a JSON document. Keep
this section and `backend/README.md` in sync.

```
GET {BASE_URL}/sessions/today?user_id=<id>
Headers: Authorization: Bearer <token>, Accept: application/json
200 application/json:
{
  "session_id": "string",
  "session_name": "string",
  "blocks": [
    { "block_name": "string",
      "exercises": [
        { "name": "string",
          "sets": number,
          "target_reps": number | null,
          "target_hold_seconds": number | null,
          "rest_seconds": number } ] } ]
}
```

Rule: `target_hold_seconds != null && > 0` ⇒ isometric hold; otherwise a reps
exercise (`target_reps` may be `null` = "to failure"). Any non-200 / transport
error / timeout ⇒ the watch falls back to its last cached session, then to the
bundled mock — **the network is never touched during a workout.**

### Logging back results (Phase C, additive — optional)

After a workout the watch may POST what was actually done, so the **next** day's
session adapts (progress when targets are met, hold/regress when missed). This is
additive: generation works fine with no logged history, so the watch can adopt it
whenever.

```
POST {BASE_URL}/sessions/log
Headers: Authorization: Bearer <token>, Content-Type: application/json
{
  "user_id": "string",
  "session_id": "string",            // the session these results belong to
  "results": [
    { "exercise": "string",
      "target_reps": number | null,
      "target_hold_seconds": number | null,
      "achieved_reps": number | null,
      "achieved_hold_seconds": number | null,
      "completed": boolean } ]
}
200 application/json: { "ok": true }
```

### Mobile ↔ server (coach-IA companion)

The mobile companion app talks **only to the server** (see `ARCHITECTURE.md`).
These three endpoints are **implemented server-side** (under `/v1`); the mobile
client that calls them is the remaining piece. The flow is propose → confirm, so
nothing reaches the watch until the athlete validates it. `<Session>` is the exact
session shape from `GET /sessions/today` above.

```
# A — talk to the coach, get a proposal
POST {BASE_URL}/coach/chat
Headers: Authorization: Bearer <token>, Content-Type: application/json
{ "user_id": "string", "message": "string" }   // the athlete's free-text message
200 application/json:
{ "reply": "string",                            // the coach's text reply
  "proposed_session": <Session> | null }        // attached once it has enough to propose

# B — confirm the day's session (this is what the watch then pulls)
POST {BASE_URL}/sessions/confirm
Headers: Authorization: Bearer <token>, Content-Type: application/json
{ "user_id": "string", "session": <Session> }   // the session the athlete accepted
200 application/json: { "ok": true }

# C — read the current program + recent adaptations
GET {BASE_URL}/program?user_id=<id>
Headers: Authorization: Bearer <token>, Accept: application/json
200 application/json:
{ "today": <Session> | null,                     // confirmed session of the day (null if none)
  "recent_changes": [ "string", ... ] }          // human-readable adaptation notes
```

## Working in this repo

- New here, or designing across bricks? Read **`ARCHITECTURE.md`** (hub model +
  mobile/server/watch flows) before touching the cross-brick wiring.
- Touching the watch app? Read and update **`watch/CLAUDE.md`** (it has the
  device matrix, flow, and the per-session "Current state" log).
- Building the backend? Put it under `backend/` and keep its responses byte-for-
  byte compatible with the contract above (Garmin requires **HTTPS** for
  `makeWebRequest`).
- **Everything stays in this single repo (monorepo).** New work goes under
  `watch/` or `backend/`; don't split bricks into separate repositories.

## Roadmap — Phase A: make generation real (backend/)

Current gap: the backend has only ever served the **built-in sample** (no API
key) or a fixed local mock. Claude has not actually generated a session yet.
Phase A closes that — it lives entirely under `backend/`, no watch changes.

**Step 1 — Real generation with an API key.**
- What: put a real `ANTHROPIC_API_KEY` in `backend/.env`, run `npm run dev`, and
  hit `GET /v1/sessions/today` — the response should now be a *Claude-generated*
  session (varied each athlete/day), not the sample.
- Why / role: validates the **core "coach IA"** end-to-end — that Claude
  (`claude-haiku-4-5`) + structured outputs (the Zod schema in
  `src/sessionSchema.ts`) reliably produce a session that satisfies the shared
  contract. This is the proof the whole architecture was built for.
- Note: no code change needed — `src/generateSession.ts` already instantiates
  `new Anthropic()` (reads `ANTHROPIC_API_KEY`) and falls back to the sample when
  the key is absent. Step 1 is configuration + observation only.

**Step 2 — Durable persistence. ✅ DONE.**
- What: the in-memory `Map` cache in `src/generateSession.ts` is replaced by
  `src/sessionStore.ts` — a durable JSON store keyed by `user_id` + date
  (`SESSIONS_DB_PATH`, default `backend/data/sessions.json`, gitignored). Atomic
  writes (temp file + rename), serialized; concurrent generations for the same
  athlete+day are deduped to a single in-flight Claude call.
- Why / role: today a generated session is lost on restart. Persistence makes
  "today's session" stable across restarts and is the **prerequisite for the
  day-to-day adaptation loop** (later Phase C: feeding logged history back to
  Claude). It also lets the 8 s watch budget stay safe — a stored session is
  served instantly instead of regenerated.
- Nuance: a Claude-generated session is persisted; when a key is present but
  generation fails transiently, the sample is served but **not** persisted, so
  the next request retries real generation instead of locking in a degraded plan.

**Done when:** a real Claude-generated session is served and validates against
the contract (Step 1), and repeated/after-restart GETs for the same athlete+day
return the same stored session (Step 2). Later phases (deploy + HTTPS, the
adaptation loop, watch polish) are tracked separately when Phase A lands.

**Status (2026-06-23): Phase A ✅ COMPLETE — validated end-to-end.** With a real
`ANTHROPIC_API_KEY` in `backend/.env`, `GET /v1/sessions/today` returns a session
**generated by Claude (`claude-haiku-4-5`)** — not the bundled sample — that
satisfies the contract (Step 1). Repeated GETs for the same athlete+day are
byte-identical, distinct `user_id`s get distinct sessions, and the served session
is persisted to `backend/data/sessions.json` and reused across restarts (Step 2).
Auth gate returns 401 without a Bearer token. Generation model was switched from
`claude-opus-4-8` to `claude-haiku-4-5` (cheaper/faster, keeps the 8 s watch
budget safe). Next up is tracked separately: deploy + HTTPS (required for the
watch's `makeWebRequest`), then the Phase C adaptation loop.

## Roadmap — next steps (post Phase A)

Phase A (real Claude generation + durable persistence) is done, the watch's
`POST /sessions/log` is built **server-side**, and the three mobile-facing
endpoints (point 1) are now implemented too. The contracts are specified above
(see "Logging back results" and "Mobile ↔ server (coach-IA companion)").
Remaining work, in rough order:

1. **Mobile-facing backend endpoints (backend/). ✅ DONE.** The three guichets are
   live under `/v1`, additive (the watch's `GET /sessions/today` + `POST
   /sessions/log` are untouched): `POST /v1/coach/chat` (athlete message → coach
   `reply` + a `proposed_session`, via Claude structured outputs in `src/coach.ts`),
   `POST /v1/sessions/confirm` (validate → `putSession` under the athlete+day key,
   so `GET /sessions/today` then serves exactly the confirmed session), `GET
   /v1/program` (today's stored session + `recent_changes`). The coach conversation
   and the adaptation notes persist per `user_id` in `src/coachStore.ts` (same
   atomic/serialized JSON discipline as `sessionStore`/`historyStore`,
   `COACH_DB_PATH`, default `./data/coach.json`). Reuses `requireBearer`,
   `zodOutputFormat`, `sessionStore`, and the in-sample fallback (`coach/chat`
   proposes the sample, `confirm`/`program` work) when no `ANTHROPIC_API_KEY`.
   Validated on localhost: propose → confirm → `GET /sessions/today` returns the
   confirmed session; `GET /program`; 401 without a token; 400 on bad payloads;
   `tsc --strict` clean; the watch GET is non-regressed. The mobile client that
   calls these (point 3) is the remaining piece.
2. **Watch → server upload (watch/). ✅ DONE — built, simulator-tested, 3 bugs
   fixed, merged in PR #3 (2026-06-23).** The on-watch app POSTs its local
   per-set log to `POST /sessions/log` after the workout; the next day's
   generation adapts. Store-and-forward and additive — the workout never touches
   the network. Three bugs surfaced on the first real simulator build and fixed:
   (a) `Content-Type` must be the CIQ enum `REQUEST_CONTENT_TYPE_JSON` (string
   caused -200, POST never left the watch); (b) `pruneForSession` must use
   `.equals()` for value comparison (identity `!=` meant the queue never drained
   → no dedup + infinite resend loop); (c) dequeue policy refined: only 400/401
   drop the item; 5xx/404/transport errors keep it queued for a later flush (true
   store-and-forward). Simulator-verified end-to-end on `fenix7x` (Enduro 2):
   exactly 1 POST → 200, history persisted, the 4 `completed` cases correct,
   queue survives restarts and flushes on launch. **Next: verify on physical
   Enduro 2** (requires HTTPS — a tunnel or a real deploy).
3. **Mobile companion brick (mobile/).** The conversational coach-IA UI that calls
   the endpoints from (1), plus viewing the adapting program. Talks only to the
   server (see `ARCHITECTURE.md`). The biggest new piece. **Status: not started.**

Also tracked separately: **deploy + HTTPS** for the backend — required for the
watch's `makeWebRequest` on a real device, and what unblocks (2) on the physical
watch.
