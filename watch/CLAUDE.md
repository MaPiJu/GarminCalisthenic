# CLAUDE.md — Connect IQ brick

Condensed project memory. Update the **Current state** section at the end of every working session.

> **Monorepo note.** This brick now lives under `watch/` in the GarminCalisthenic
> monorepo (alongside the future `backend/`). All paths below are relative to
> `watch/`; open/build this folder as the project root in the Monkey C extension
> (the jungle's default discovery is unchanged). The shared JSON contract and the
> repo map are in the root `../CLAUDE.md`.

## Goal of this Connect IQ brick

On-watch app that runs **during** a calisthenics session. It loads the day's
session, shows a recap, walks the user through each exercise (set X/Y, target
reps OR isometric hold), runs the rest and hold timers (with vibration), lets
the user validate each set (and adjust the reps actually done), and logs every
validated set **locally and immediately** — no network dependency during the
workout. This brick is *only* the watch app. The backend (Claude-driven session
generation) and the mobile companion are out of scope for now.

## Data contract (session JSON)

Today this is a bundled mock resource (`resources/json/mock_session.json`).
Later the exact same shape will arrive from the backend via a single grouped
`Communications.makeWebRequest` call per session. The parser is source-agnostic.

```json
{
  "session_id": "string",
  "session_name": "string",
  "blocks": [
    {
      "block_name": "string",
      "exercises": [
        {
          "name": "string",
          "sets": number,
          "target_reps": number | null,
          "target_hold_seconds": number | null,
          "rest_seconds": number
        }
      ]
    }
  ]
}
```

Rule: `target_hold_seconds != null && > 0` ⇒ isometric hold exercise; otherwise
it is a reps exercise (`target_reps` may be `null` = "to failure", user enters
the actual count).

## Target devices (exactly 5 — do not add others yet)

| Device          | Product id(s) in manifest                                            | Input            | Screen        | Tier        |
|-----------------|----------------------------------------------------------------------|------------------|---------------|-------------|
| Fenix 8 (AMOLED)| `fenix843mm`, `fenix847mm`                                            | touch + buttons  | AMOLED round  | high-mem    |
| Forerunner 970  | `fr970`                                                              | touch + buttons  | AMOLED round  | high-mem    |
| Venu 4          | `venu441mm`, `venu445mm`                                              | touch (+2 btn)   | AMOLED round  | high-mem    |
| Instinct 3      | `instinct3amoled45mm`, `instinct3amoled50mm` (AMOLED) / `instinct3solar45mm` (MIP) | buttons only | AMOLED or MIP | AMOLED=high / Solar(MIP)=constrained |
| **Enduro 2**    | **`fenix7x`** (real target — see below)                              | touch + buttons  | MIP round     | high-mem — **PRIORITY device** |

> **Enduro 2 mapping (important).** The Enduro 2 has **no dedicated CIQ profile**:
> its part number sits inside the **`fenix7x`** device definition, so `fenix7x` is
> the build target that actually installs on a physical Enduro 2 (it also pulls in
> the Fenix 7/7X family). Consequences: (1) the Enduro 2 is a **high-memory**
> device, not constrained — it gets the real HR recorder; (2) it has a
> **touchscreen** + buttons, so it shows "Tap" hints. We also keep **`enduro`**
> (the older Enduro 1, CIQ 3.4.2, MIP, buttons-only) as a conservative
> *constrained* test target — if the flow works there it works on the Enduro 2.
> Verify definitively by **sideloading the .prg to the real Enduro 2**.

Why these 5: popularity + they span the full Garmin input/screen diversity
(touch / hybrid / buttons-only, AMOLED / MIP). **Enduro 2 is the real personal
device** → always validate first in the simulator (via `fenix7x`, plus the
constrained `enduro`); if a trade-off must favor one device, favor the Enduro 2.

> ⚠️ Product-id strings are SDK-version specific. They were chosen from the best
> available references but Garmin's device pages were unreachable at setup time.
> If a build fails with "Invalid device ID", regenerate the product list from
> the VS Code Monkey C extension (manifest editor → "Edit Products", which lists
> the devices actually installed in your SDK) and update both `manifest.xml` and
> the per-product lines in `monkey.jungle`.

## Compatibility & device handling

- **minApiLevel = 3.1.0.** Lowest level that still provides everything we use:
  `Application.Storage` (since 2.4.0), `Communications.makeWebRequest` (3.0.0),
  `Timer` / `WatchUi` (1.x), and `jsonData` resources (3.1.0, used for the mock).
  All 5 targets are System 5–7 (API 4.x–5.x), far above this, so keeping the
  floor low maximizes future device coverage without losing any feature we need.
- **Input abstraction (runtime, not compile-time):** `ActionDelegate`
  (`source/ui/ActionDelegate.mc`) maps both `onKey` (buttons: ENTER=action,
  UP/DOWN=adjust, ESC→`onBack`=cancel) **and** `onTap` (touch zones: top=up,
  bottom=down, middle=action) onto four semantic actions. `onTap` is gated by
  `System.getDeviceSettings().isTouchScreen` checked **at runtime**, because the
  Fenix 8 can run in either mode. Views render different hints ("Tap" vs "START")
  based on the same runtime flag.
- **Relative layout:** `source/ui/Layout.mc` positions everything as fractions
  of `screenWidth`/`screenHeight` and reads `screenShape` (round vs rectangle).
  No fixed pixel coordinates.
- **Graceful memory degradation:** the optional parallel HR `ActivityRecording`
  feature lives behind `RecordingHook`. Two implementations expose the same API:
  `RecordingHook.mc` (`:hrRecording`, real) and `RecordingHookStub.mc`
  (`:noHrRecording`, no-op). `monkey.jungle` excludes the heavy one on the
  genuinely constrained MIP variants (Enduro 1 `enduro`, Instinct 3 Solar
  `instinct3solar45mm`) and the stub everywhere else. The Enduro 2 builds as
  `fenix7x` (high memory), so it keeps the real recorder. The core flow (session
  display + timers + local logging) never depends on it, so it works on every
  target. (The `Fit` permission is now in the manifest, so on capable devices
  `RecordingHook.start()` really starts a recording and `stop(true)` saves a FIT
  activity — pass `stop(false)` to discard during testing.)

## Architecture decisions

- **Local-first logging:** every validated set is written to
  `Application.Storage` immediately (`SessionLogger`). Zero network during a
  workout.
- **One grouped network call per session (future):** the data layer
  (`SessionRepository`) is isolated from the UI. Today it loads the mock JSON
  resource; swapping in `makeWebRequest` only changes that one class — the parser
  and models (`parseSession` → `Session`/`Block`/`Exercise`) are identical
  because `makeWebRequest` yields the same `Dictionary` shape as the resource.
- **Input/display/data separation:** `data/` (repository, logger, recording
  hook), `model/` (plain data objects + parser), `ui/` (views, delegate, layout,
  controller). `WorkoutController` owns progression state and all view
  transitions; views are dumb renderers + semantic-action handlers.
- **Single forwarding delegate:** `ScreenDelegate` forwards the four semantic
  actions to whichever view is active (`handleAction/handleUp/handleDown/
  handleCancel`), so there is one input class, not one per screen.
- **Transitions via `switchToView`** (not `pushView`) to keep one view alive at a
  time — lighter for the constrained devices.

## Flow

Summary → (start) → ExerciseView(set X/Y, target). For a reps set: action →
inline rep-adjust (pre-filled with target, up/down) → confirm logs the set. For
a hold set: action → HoldView countdown (vibrate at 0) logs the set. After each
set (except the session's last) → RestView countdown (vibrate at 0) → next set/
exercise. After the last set → FinishView (sets done, total reps, elapsed).

## Current state

Updated: 2026-06-23

Done:
- Project scaffold: `manifest.xml` (5 devices, minApiLevel 3.1.0), `monkey.jungle`
  (memory-degradation annotations), resources (strings, launcher icon, mock JSON).
- Models + parser (`SessionModel.mc`), `SessionRepository` (mock JSON loader,
  network-ready), `SessionLogger` (immediate local storage).
- Input abstraction (`ActionDelegate` + `ScreenDelegate`), relative `Layout`,
  `Theme`.
- Full base flow: Summary → Exercise (reps adjust + hold) → Rest/Hold timers
  with vibration → local logging → Finish recap. `WorkoutController` state machine.
- HR `ActivityRecording` scaffolding (real + stub) wired through `RecordingHook`,
  excluded on Enduro / Instinct 3 Solar.
- **SDK 9.2.0 verified + full simulator test on Enduro (CIQ 3.4.2) passed.**
  All 5 screens rendered and navigated end-to-end. Fixed: `Lang.Array` cast in
  SessionLogger, `as Void` on Timer callbacks (HoldView/RestView), removed "x "
  prefix from FONT_NUMBER_MEDIUM in ExerciseView (letters render as empty boxes).
- Product IDs corrected: `instinct3solar50mm` removed (SDK has only
  `instinct3solar45mm`). Enduro 2 understood correctly — it has no own CIQ
  profile, its part number lives under `fenix7x`, so **`fenix7x` added** as the
  real Enduro 2 target; `enduro` (Enduro 1, CIQ 3.4.2) kept as a constrained test
  target. (Supersedes the earlier `enduro2`→`enduro` note.)
- **All 5 devices simulator-tested end-to-end (2026-06-22).** Added `Fit`
  permission to manifest (required by SDK 9.2 type checker for `RecordingHook.mc`
  on high-mem devices, even with try/catch guard). Touch/button hint switching
  verified: "Tap" on fenix843mm/fr970/venu441mm, "START" on instinct3amoled45mm
  and enduro. AMOLED rendering clean on all round screens.
- **`fenix7x` (Enduro 2 real target) simulator-tested end-to-end (2026-06-22).**
  RestView, countdown timer, and "tap: skip" hint all render correctly on the MIP
  round screen. Touch hints confirmed ("tap", not "START") — fenix7x is high-mem
  with touchscreen. This is the ground truth that the Enduro 2 part-number mapping
  is correct; sideload the `fenix7x` .prg to the physical device to confirm.
- **Backend wiring (client side) — the grouped network fetch + resilience.**
  - API contract frozen in `source/data/ApiConfig.mc` (endpoint, auth header,
    user id, timeout): `GET {BASE_URL}/sessions/today?user_id=<id>` with
    `Authorization: Bearer <token>`, returning the *exact* `mock_session.json`
    shape. URL/token are documented placeholders; `userId()`/`authToken()` read
    from `Storage` (to be provisioned by the future companion) with dev defaults.
  - `SessionRepository.loadSession()` (sync mock) replaced by async
    `fetchSession(callback)`: ONE grouped `Communications.makeWebRequest` per
    session, BEFORE the workout. Resilience ladder: 200 → parse + cache raw JSON
    (`:ok`); error/timeout + cache present → replay last cached session
    (`:offlineCache`); no cache → bundled mock (`:offlineMock`); nothing → `:error`.
    Explicit guard `Timer` (`ApiConfig.REQUEST_TIMEOUT_MS`, 8s) + `_responded`
    flag guarantees the callback fires exactly once; sync throw from
    makeWebRequest is caught and routed to the offline fallback too.
  - New `LoadingView` is now the initial view: kicks the fetch on `onShow`, then
    the controller `switchToView`s to Summary as soon as a session exists. A hard
    failure shows a retry affordance. `WorkoutController.load()` → async
    `beginLoad`/`onSessionLoaded`/`retryLoad`/`setSession`/`showSummary`.
  - `SummaryView` shows an **OFFLINE** flag (vs **TODAY**) when the plan came
    from cache/mock (`controller.isOffline`). Parser + models unchanged — the
    seam stayed isolated to `SessionRepository` exactly as designed.
  - The network never runs during the workout: local-first logging is untouched.
- **All 4 fetch paths simulator-tested on `fenix7x` (Enduro 2) — SDK 9.2.0
  (2026-06-22).** Required a real build-fix first: `onReceive(responseCode, data)`
  was untyped, so SDK 9.2's checker rejected `method(:onReceive)` as the
  `makeWebRequest` callback (this async code had never been compiled). Fixed by
  annotating the signature to the exact `Communications` callback PolyType
  (`Number`, `Null or Dictionary or String or PersistedContent.Iterator`, `as Void`).
  Then exercised each rung end-to-end via screen captures:
  - `:offlineMock` — unreachable URL + no cache → Loading → Summary **OFFLINE** /
    "Push & Core" (mock); ran the whole flow Exercise→rep-adjust→Rest→Hold→
    **Finish (16/16 sets, 128 reps)** with no network.
  - `:ok` — local HTTP server returning the contract (distinct "Server Pull Day");
    Summary shows **TODAY** + the server session; JSON cached to `cached_session_json`.
  - `:offlineCache` — back to unreachable URL, cache intact → **OFFLINE** but the
    *cached server* session ("Server Pull Day"), NOT the mock. Proves caching +
    cache-replay rung.
  - timeout — host that accepts the TCP connection but never responds: Loading
    persisted ~7–8s (the `REQUEST_TIMEOUT_MS` guard), then fell back **OFFLINE**
    (→ mock with cache cleared, → cache otherwise). Guard timer confirmed.
  - Test harness (no Screen-Recording-free path needed once granted): build with
    `monkeyc -d fenix7x -y developer_key`, `monkeydo … fenix7x`; drive the sim via
    AppleScript/AX menu clicks + Quartz mouse taps (pyobjc) on the watch screen
    centre (~1223,300); capture with `screencapture -R<win-rect>`. HTTP path tests
    use a local `python3 -m http.server`-style server + Settings → *Use Device
    HTTPS Requirements* toggled OFF so `http://127.0.0.1` is accepted.
- **Watch → server upload (the watch half of the adaptation loop) — built &
  simulator-tested (2026-06-23).** After a workout the app now POSTs what was
  actually done to `POST {BASE_URL}/sessions/log`, so the next day's generation
  adapts. Store-and-forward, additive, and the workout still never touches the
  network:
  - `ApiConfig.mc` gains `logUrl()` (`BASE_URL + "/sessions/log"`) and
    `uploadHeaders()` (`Authorization` + JSON `Content-Type`); the POST contract
    is documented next to the GET one.
  - `SessionLogger.resultsForUpload(sessionId)` reads the local `log:<id>` array
    and maps each validated set onto the server contract: `actual_reps` /
    `actual_hold_seconds` → `achieved_*`, and derives `completed` (held ≥ target,
    or reps ≥ target; a *to-failure* set counts as completed once any reps were
    logged). One result entry per set.
  - New `data/LogUploader.mc` — durable store-and-forward queue in `Storage`
    (`upload_queue`, bounded, de-duped per `session_id`). `flush()` drains it
    sequentially, one `makeWebRequest` in flight, with the SAME timeout-guard +
    fire-once discipline as `SessionRepository`. Dequeue policy: `200` → drop &
    continue; `400`/`401` (the payload itself is bad) → drop too so a poison item
    can't block the queue; **everything else — 5xx, a 404 from a down backend, or
    a transport error / timeout (offline) → keep & stop, retried on a later
    flush** (true store-and-forward; a transient server error never loses a log).
  - `WorkoutController`: holds a `LogUploader`; `showFinish()` enqueues the
    finished log + `flush()`es it; `beginLoad()` also `flush()`es at launch, so a
    log that couldn't go out earlier (no phone / BLE / server down) is retried on
    the next connected run. The summary/`endSession` path is unchanged.
  - **Note on nulls:** the server schema is strict (`.nullable()`, not optional),
    so each result MUST carry all six keys; the watch emits explicit `null`s and
    relies on CIQ's JSON serializer including null-valued Dictionary entries.
    Verified cross-brick against the real backend `POST /v1/sessions/log` (payload
    accepted → 200, history persisted; omitting the null keys → 400). The
    simulator-captured POST body confirmed CIQ keeps `null`-valued entries.
  - **Two real build/runtime bugs found on the first simulator build (this code
    had never been compiled) and fixed (2026-06-23):**
    - *Content-Type header* — `uploadHeaders()` sent the **string**
      `"application/json"`, which `makeWebRequest` rejects as an invalid header
      field (response code `-200`, never leaves the watch). Fixed to the CIQ enum
      constant `Communications.REQUEST_CONTENT_TYPE_JSON` (+ `using
      Toybox.Communications;` in `ApiConfig.mc`). The GET path was unaffected (it
      only sends `Accept`).
    - *Queue never drained / no dedup* — `pruneForSession` compared `session_id`
      with `!=` on a statically-`Object` value, i.e. identity comparison that
      never matched, so the queue never shrank → no dedup **and** an infinite
      resend loop (~800 req/s once POSTs returned `200`). Fixed to value
      comparison (`.equals()`).
  - **Simulator-verified end-to-end on `fenix7x` (Enduro 2), HTTPS-requirements
    OFF:** after the fixes, exactly one `POST /sessions/log` → `200`, queue
    drained, backend `history.json` grows; the four `completed` cases
    (reps-met=true, reps-low=false, hold-stopped-early=false, to-failure=true)
    are correct in the captured body; the durable queue survived ~5 app restarts
    and flushed on launch; finishing offline never blocks the DONE screen.
  - **Caveat (real-device vs simulator):** a *down* backend returns different
    things in each — the simulator answers `404` (host refused), a real device
    returns a negative transport code. The retry policy above keeps the log in
    BOTH cases (404 and negative both fall to the "keep & retry" branch), so this
    is no longer a data-loss risk; only a true `400`/`401` drops an item.

To do / next sessions:
- **Verify the upload on the physical Enduro 2** (the simulator pass above covers
  `fenix7x`): the physical-device path is exactly where the real `-200`-style
  transport codes and HTTPS requirement bite, so sideload the `fenix7x` .prg and
  confirm one `POST /sessions/log` → 200 against an HTTPS backend, plus the
  offline-queue-then-flush-on-launch behaviour.
- (Optional) repeat the 4 fetch paths on the other 4 devices; behaviour is
  device-agnostic (seam is isolated in `SessionRepository`), so fenix7x is
  representative.
- Verify on the **physical Enduro 2** by sideloading the `fenix7x` .prg (simulator
  already confirmed MIP rendering + touch hints; physical test validates the
  part-number mapping end-to-end).
- Server brick (separate, out of scope for the watch): stand up
  `GET /sessions/today` that calls the Claude API to generate/adapt the plan and
  returns the contract JSON; then flip `ApiConfig.BASE_URL` to the real host and
  provision `user_id`/`auth_token` (companion pairing).
- Decide & flesh out `RecordingHook` (lap markers per set, etc.) — `Fit`
  permission already in manifest.
- Polish: long-name truncation per screen size, count-up hold option, settings.
- **Exercise GIF/animation integration (future):** Garmin embeds animated exercise
  illustrations (push-ups, pull-ups, etc.) in its built-in workout app. These are
  device-specific assets — available on AMOLED high-mem devices, likely absent on
  MIP/constrained ones. Investigate `WatchUi.AnimationLayer` or bundled `AnimatedBitmap`
  resources as the mechanism; gate behind a runtime capability check so it degrades
  gracefully (text-only fallback on Enduro 1 / Instinct 3 Solar). Map exercise names
  in the session JSON to the corresponding Garmin asset IDs per device family.
