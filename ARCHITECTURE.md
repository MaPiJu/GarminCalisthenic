# ARCHITECTURE.md — GarminCalisthenic

How the pieces fit together, and the one rule that keeps them decoupled.
Companion to the root `CLAUDE.md` (repo map + shared contract).

## Principle: the server is the hub

The **server is the single source of truth and the AI brain.** The mobile app
and the watch are both thin clients of the backend; **they only ever talk to the
server — never directly to each other.**

```
   chat with coach-IA, give feedback,      source of truth +          pulls today's session,
   define / view the adapting program       AI brain (Claude) +        uploads what was done
        ┌───────────┐       ⇄        ┌──────────────────────────┐       ⇄       ┌───────────┐
        │  Mobile   │                │   SERVER  (backend/)     │               │   Watch   │
        │   app     │                │  generate · store · adapt│               │ (ConnectIQ)│
        └───────────┘                └──────────────────────────┘               └───────────┘
```

## The decision: mobile → server → watch  (NOT mobile → watch direct)

Garmin *can* do phone↔watch messaging (Connect IQ Mobile SDK over the Garmin
Connect BLE bridge), but we deliberately do **not** use it for the training plan:

- **The server is in the loop anyway** (it hosts the AI and receives the upload),
  so a direct phone→watch channel adds a fragile transport without removing the
  server — more complexity, no gain.
- **Time-decoupling.** Define the session on the phone now, run it on the watch
  later: the watch just pulls "today's session" when it next connects. No
  phone-present / app-open requirement at workout time.
- **Pull beats push for a wearable** (battery, connectivity windows) and already
  has an offline ladder (cached session → bundled mock).
- **One source of truth.** The server already stores sessions + history; a direct
  push would bypass it and force re-sync.

Note: "server → watch" is realised as **the watch pulling from the server** — which
is exactly how it already works today.

## Flows

1. **Define / adapt (mobile ⇄ server).** The athlete chats with the coach-IA in the
   mobile app; the server asks Claude and stores the resulting session + program.
   *Endpoints `POST /coach/chat` (propose) → `POST /sessions/confirm` (validate) →
   `GET /program` (read adaptations) are **built server-side**; the mobile client
   that calls them is the remaining piece.*
2. **Fetch (watch pulls from server).** Before a workout the watch calls
   `GET /v1/sessions/today?user_id=<id>` and caches it; offline ladder if the
   network is unreachable. **Built.**
3. **Do the workout (watch, offline).** The watch walks the athlete through each
   set, runs the timers, and logs every set locally and immediately — zero network
   during the workout. **Built.**
4. **Upload (watch → server).** After the workout the watch POSTs the actual results
   to `POST /v1/sessions/log` (logged locally, sent when online). *Server half built;
   watch half to build.*
5. **Analyze + adapt (server, then mobile reads).** The server folds the logged
   history into the next generation (progress when targets met, hold/regress when
   missed); the mobile app reads the adapted program back from the server.
   *Server-side adaptation built; mobile read + richer adaptation to come.*

## Bricks

- **`backend/`** — the hub. Claude generation, durable persistence, the watch↔server
  contract endpoints. See `backend/README.md`.
- **`watch/`** — the on-watch Connect IQ app. Pull + offline resilience, local-first
  logging, the full on-watch flow. See `watch/CLAUDE.md`.
- **`mobile/`** *(future)* — the companion app: conversational coach-IA to define
  sessions and capture feedback, and to view the adapting program. The biggest new
  piece; it talks only to the server.

## Contract

The watch↔server JSON contract (`GET /sessions/today`, `POST /sessions/log`) lives
in the root `CLAUDE.md` and is the source of truth. Keep that, this file, and
`backend/README.md` in sync. The mobile↔server endpoints (`POST /coach/chat`,
`POST /sessions/confirm`, `GET /program`) are specified there too and are now
**implemented server-side** (the mobile client remains to be built).

## Status (2026-06-23)

- ✅ Server brick: Claude generation (`claude-haiku-4-5`), durable persistence,
  `POST /sessions/log`, and the mobile-facing coach-IA endpoints
  (`POST /coach/chat`, `POST /sessions/confirm`, `GET /program`).
- ✅ Watch brick: pull + offline resilience, local-first logging, full on-watch flow.
- 🔜 Watch → server upload (the watch half of the adaptation loop).
- 🆕 Mobile app: the conversational coach-IA UI on top of the endpoints above
  (the biggest new piece — server side is ready).
