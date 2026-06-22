# CLAUDE.md — Connect IQ brick

Condensed project memory. Update the **Current state** section at the end of every working session.

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

Updated: 2026-06-22

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

To do / next sessions:
- Verify on the **physical Enduro 2** by sideloading the `fenix7x` .prg (simulator
  already confirmed MIP rendering + touch hints; physical test validates the
  part-number mapping end-to-end).
- Replace mock loader with the grouped `makeWebRequest` call (backend brick).
- Decide & flesh out `RecordingHook` (lap markers per set, etc.) — `Fit`
  permission already in manifest.
- Optional: persist/queue finished-session logs for later upload by the companion.
- Polish: long-name truncation per screen size, count-up hold option, settings.
