using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Timer;

// Rest countdown between sets. Vibrates at 0 and auto-advances. The user can
// skip (action) or nudge the remaining time (+/- 15 s) with up/down.
class RestView extends WatchUi.View {

    private var _c;          // WorkoutController
    private var _remaining;  // seconds
    private var _timer;
    private var _done;

    function initialize(controller, seconds) {
        View.initialize();
        _c = controller;
        _remaining = seconds;
        _done = false;
    }

    function onShow() {
        _timer = new Timer.Timer();
        _timer.start(method(:onTick), 1000, true);
    }

    function onHide() {
        stopTimer();
    }

    private function stopTimer() {
        if (_timer != null) {
            _timer.stop();
            _timer = null;
        }
    }

    function onTick() {
        _remaining -= 1;
        if (_remaining <= 0) {
            _remaining = 0;
            finish();
        } else {
            WatchUi.requestUpdate();
        }
    }

    private function finish() {
        if (_done) {
            return;
        }
        _done = true;
        stopTimer();
        Feedback.vibrateEnd();
        _c.onRestDone();
    }

    function onUpdate(dc) {
        Layout.clear(dc);
        Layout.centerText(dc, 0.20, Graphics.FONT_XTINY, Theme.ACCENT, "REST");

        // Next-up preview
        Layout.centerText(dc, 0.33, Graphics.FONT_TINY, Theme.DIM,
            "Next: " + _c.currentExercise().name);

        Layout.centerText(dc, 0.55, Graphics.FONT_NUMBER_THAI_HOT, Theme.FG,
            Layout.fmtClock(_remaining));

        Layout.centerText(dc, 0.86, Graphics.FONT_XTINY, Theme.ACCENT,
            Layout.isTouch() ? "tap: skip" : "START: skip");
    }

    // ----- Semantic actions ------------------------------------------------
    function handleAction() {
        finish(); // skip the rest of the rest
        return true;
    }

    function handleUp() {
        _remaining += 15;
        WatchUi.requestUpdate();
        return true;
    }

    function handleDown() {
        _remaining -= 15;
        if (_remaining <= 0) {
            finish();
        } else {
            WatchUi.requestUpdate();
        }
        return true;
    }

    function handleCancel() {
        finish();
        return true;
    }
}
