using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.System;

// End-of-session recap. All sets are already logged locally by this point.
class FinishView extends WatchUi.View {

    private var _c;        // WorkoutController
    private var _elapsed;  // seconds

    function initialize(controller, elapsedSeconds) {
        View.initialize();
        _c = controller;
        _elapsed = elapsedSeconds;
    }

    function onUpdate(dc) {
        Layout.clear(dc);

        Layout.centerText(dc, 0.16, Graphics.FONT_SMALL, Theme.ACCENT, "DONE");
        Layout.centerText(dc, 0.28, Graphics.FONT_TINY, Theme.FG, _c.session.name);

        Layout.centerText(dc, 0.45, Graphics.FONT_MEDIUM, Theme.FG,
            _c.completedSets + "/" + _c.totalSets + " sets");
        Layout.centerText(dc, 0.58, Graphics.FONT_SMALL, Theme.DIM,
            _c.totalReps + " reps");
        Layout.centerText(dc, 0.70, Graphics.FONT_SMALL, Theme.DIM,
            Layout.fmtClock(_elapsed));

        Layout.centerText(dc, 0.88, Graphics.FONT_XTINY, Theme.ACCENT,
            Layout.isTouch() ? "tap: exit" : "START: exit");
    }

    // ----- Semantic actions ------------------------------------------------
    function handleAction() {
        System.exit();
        return true;
    }

    function handleUp() {
        return false;
    }

    function handleDown() {
        return false;
    }

    function handleCancel() {
        System.exit();
        return true;
    }
}
