using Toybox.WatchUi;
using Toybox.Graphics;

// Active-set screen. Two internal phases:
//   PROMPT  - shows the exercise, "Set X/Y" and the target.
//             action -> start hold (hold exercise) OR enter rep-adjust (reps).
//   ADJUST  - reps exercises only: edit the reps actually done (pre-filled with
//             the target), then confirm to log the set.
class ExerciseView extends WatchUi.View {

    private var _c; // WorkoutController

    private const PHASE_PROMPT = 0;
    private const PHASE_ADJUST = 1;
    private var _phase;
    private var _reps; // working rep count while adjusting

    function initialize(controller) {
        View.initialize();
        _c = controller;
        _phase = PHASE_PROMPT;
    }

    function onUpdate(dc) {
        Layout.clear(dc);
        var ex = _c.currentExercise();

        if (_phase == PHASE_ADJUST) {
            drawAdjust(dc, ex);
        } else {
            drawPrompt(dc, ex);
        }
    }

    private function drawPrompt(dc, ex) {
        // Block name + exercise position
        Layout.centerText(dc, 0.12, Graphics.FONT_XTINY, Theme.ACCENT,
            _c.currentBlockName() + "  " + _c.currentExerciseNumber() + "/" + _c.exerciseCount());

        // Exercise name
        Layout.centerText(dc, 0.30, Graphics.FONT_MEDIUM, Theme.FG, ex.name);

        // Set X/Y
        Layout.centerText(dc, 0.46, Graphics.FONT_SMALL, Theme.DIM,
            "Set " + _c.currentSetIndex() + "/" + ex.sets);

        // Target: reps or hold
        if (ex.isHold()) {
            Layout.centerText(dc, 0.62, Graphics.FONT_NUMBER_MEDIUM, Theme.FG,
                Layout.fmtClock(ex.targetHoldSeconds));
            Layout.centerText(dc, 0.80, Graphics.FONT_XTINY, Theme.DIM, "HOLD");
        } else if (ex.targetReps != null) {
            // FONT_NUMBER_MEDIUM only has digit glyphs — no letters, so no prefix.
            Layout.centerText(dc, 0.62, Graphics.FONT_NUMBER_MEDIUM, Theme.FG,
                ex.targetReps.toString());
            Layout.centerText(dc, 0.80, Graphics.FONT_XTINY, Theme.DIM, "REPS");
        } else {
            Layout.centerText(dc, 0.62, Graphics.FONT_LARGE, Theme.FG, "MAX");
            Layout.centerText(dc, 0.80, Graphics.FONT_XTINY, Theme.DIM, "REPS");
        }

        // Action hint
        var hint = ex.isHold()
            ? (Layout.isTouch() ? "Tap: start hold" : "START: hold")
            : (Layout.isTouch() ? "Tap: done" : "START: done");
        Layout.centerText(dc, 0.91, Graphics.FONT_XTINY, Theme.ACCENT, hint);
    }

    private function drawAdjust(dc, ex) {
        Layout.centerText(dc, 0.14, Graphics.FONT_XTINY, Theme.ACCENT, "REPS DONE");
        Layout.centerText(dc, 0.26, Graphics.FONT_SMALL, Theme.DIM, ex.name);

        // Up / down affordances + the editable number
        Layout.centerText(dc, 0.40, Graphics.FONT_TINY, Theme.DIM,
            Layout.isTouch() ? "tap top +" : "UP +");
        Layout.centerText(dc, 0.56, Graphics.FONT_NUMBER_HOT, Theme.FG, _reps.format("%d"));
        Layout.centerText(dc, 0.74, Graphics.FONT_TINY, Theme.DIM,
            Layout.isTouch() ? "tap bottom -" : "DOWN -");

        Layout.centerText(dc, 0.90, Graphics.FONT_XTINY, Theme.ACCENT,
            Layout.isTouch() ? "tap mid: confirm" : "START: confirm");
    }

    // ----- Semantic actions ------------------------------------------------
    function handleAction() {
        var ex = _c.currentExercise();
        if (_phase == PHASE_PROMPT) {
            if (ex.isHold()) {
                _c.showHold();
            } else {
                // Enter rep-adjust, pre-filled with the target (0 if "max").
                _reps = ex.targetReps != null ? ex.targetReps : 0;
                _phase = PHASE_ADJUST;
                WatchUi.requestUpdate();
            }
        } else {
            // Confirm reps -> log + advance.
            _c.completeSet(_reps, null);
        }
        return true;
    }

    function handleUp() {
        if (_phase == PHASE_ADJUST) {
            _reps += 1;
            WatchUi.requestUpdate();
            return true;
        }
        return false;
    }

    function handleDown() {
        if (_phase == PHASE_ADJUST && _reps > 0) {
            _reps -= 1;
            WatchUi.requestUpdate();
            return true;
        }
        return false;
    }

    function handleCancel() {
        // While adjusting, back returns to the prompt instead of exiting.
        if (_phase == PHASE_ADJUST) {
            _phase = PHASE_PROMPT;
            WatchUi.requestUpdate();
            return true;
        }
        return false;
    }
}
