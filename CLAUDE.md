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
| Instinct 3      | `instinct3amoled45mm`, `instinct3amoled50mm` (AMOLED) / `instinct3solar45mm`, `instinct3solar50mm` (MIP) | buttons only | AMOLED or MIP | AMOLED=high / Solar(MIP)=constrained |
| **Enduro 2**    | `enduro2`                                                            | buttons only     | MIP round     | **constrained — PRIORITY test device** |

Why these 5: popularity + they span the full Garmin input/screen diversity
(touch / hybrid / buttons-only, AMOLED / MIP). **Enduro 2 is the real personal
device** → always validate on Enduro 2 first in the simulator; if a trade-off
must favor one device, favor the Enduro 2.

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
  constrained variants (Enduro 2, Instinct 3 Solar/MIP) and the stub everywhere
  else. The core flow (session display + timers + local logging) never depends
  on it, so it works on all 5. (HR recording also needs an activity-record
  permission added to the manifest before it actually records — left off by
  default so base testing has no save prompts.)

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

Updated: 2026-06-19

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
- Product IDs corrected: `enduro2` → `enduro` (shared CIQ profile);
  `instinct3solar50mm` removed (SDK has only `instinct3solar45mm`, covers both).

To do / next sessions:
- Test on the other 4 devices in the simulator (fenix843mm, fr970, venu441mm,
  instinct3amoled45mm) — check AMOLED rendering and touch hint display.
- Replace mock loader with the grouped `makeWebRequest` call (backend brick).
- Decide & add the activity-record permission if HR capture is wanted; flesh out
  `RecordingHook` (lap markers per set, etc.).
- Optional: persist/queue finished-session logs for later upload by the companion.
- Polish: long-name truncation per screen size, count-up hold option, settings.
