using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Timer;

// Isometric hold timer: counts DOWN from target_hold_seconds, vibrates at 0 and
// logs the set automatically. The user can also stop early (action), which logs
// the elapsed hold time actually achieved.
class HoldView extends WatchUi.View {

    private var _c;          // WorkoutController
    private var _target;     // seconds
    private var _remaining;  // seconds
    private var _timer;
    private var _done;

    function initialize(controller) {
        View.initialize();
        _c = controller;
        _target = controller.currentExercise().targetHoldSeconds;
        _remaining = _target;
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
            complete(_target); // full hold achieved
        } else {
            WatchUi.requestUpdate();
        }
    }

    // Log the achieved hold seconds and move on (rest / next / finish).
    private function complete(achievedSeconds) {
        if (_done) {
            return;
        }
        _done = true;
        stopTimer();
        Feedback.vibrateEnd();
        _c.completeSet(null, achievedSeconds);
    }

    function onUpdate(dc) {
        Layout.clear(dc);
        var ex = _c.currentExercise();

        Layout.centerText(dc, 0.18, Graphics.FONT_XTINY, Theme.ACCENT, "HOLD");
        Layout.centerText(dc, 0.31, Graphics.FONT_TINY, Theme.DIM,
            ex.name + "  " + _c.currentSetIndex() + "/" + ex.sets);

        Layout.centerText(dc, 0.55, Graphics.FONT_NUMBER_THAI_HOT, Theme.FG,
            Layout.fmtClock(_remaining));

        Layout.centerText(dc, 0.86, Graphics.FONT_XTINY, Theme.ACCENT,
            Layout.isTouch() ? "tap: stop" : "START: stop");
    }

    // ----- Semantic actions ------------------------------------------------
    function handleAction() {
        complete(_target - _remaining); // stopped early -> elapsed time
        return true;
    }

    function handleUp() {
        return false;
    }

    function handleDown() {
        return false;
    }

    function handleCancel() {
        complete(_target - _remaining);
        return true;
    }
}
