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
└── backend/       ← Future server brick: a service that calls the Claude API
                     to generate/adapt a session and returns the contract JSON.
                     Not built yet. See backend/README.md.
```

## Bricks

- **watch/** — the on-watch calisthenics coach. Loads the day's session, walks
  the user through each set, runs rest/hold timers, validates and logs every set
  **locally and immediately**. Fully working today; full details, target devices,
  architecture and current state live in **`watch/CLAUDE.md`**.
- **backend/** — the "coach IA" service. Out of scope as code for now; its only
  obligation is to return the JSON contract below. The watch already speaks to it
  through `watch/source/data/ApiConfig.mc` (endpoint, auth, timeout) +
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
