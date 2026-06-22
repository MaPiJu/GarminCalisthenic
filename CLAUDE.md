# CLAUDE.md — GarminCalisthenic monorepo

Top-level project memory. Each **brick** keeps its own detailed `CLAUDE.md`;
this file is just the map and the one thing both bricks must agree on.

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
  (`claude-opus-4-8`, structured outputs) and returns the JSON contract below;
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

## Working in this repo

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
  (`claude-opus-4-8`) + structured outputs (the Zod schema in
  `src/sessionSchema.ts`) reliably produce a session that satisfies the shared
  contract. This is the proof the whole architecture was built for.
- Note: no code change needed — `src/generateSession.ts` already instantiates
  `new Anthropic()` (reads `ANTHROPIC_API_KEY`) and falls back to the sample when
  the key is absent. Step 1 is configuration + observation only.

**Step 2 — Durable persistence.**
- What: replace the in-memory `Map` cache in `src/generateSession.ts` with a
  durable store (start simple: SQLite or a JSON file), keyed by `user_id` + date.
- Why / role: today a generated session is lost on restart. Persistence makes
  "today's session" stable across restarts and is the **prerequisite for the
  day-to-day adaptation loop** (later Phase C: feeding logged history back to
  Claude). It also lets the 8 s watch budget stay safe — a stored session is
  served instantly instead of regenerated.

**Done when:** a real Claude-generated session is served and validates against
the contract (Step 1), and repeated/after-restart GETs for the same athlete+day
return the same stored session (Step 2). Later phases (deploy + HTTPS, the
adaptation loop, watch polish) are tracked separately when Phase A lands.
