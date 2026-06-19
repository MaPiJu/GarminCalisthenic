using Toybox.WatchUi;
using Toybox.Graphics;

// Session recap screen: name, block list, estimated duration, start hint.
class SummaryView extends WatchUi.View {

    private var _c; // WorkoutController

    function initialize(controller) {
        View.initialize();
        _c = controller;
    }

    function onUpdate(dc) {
        Layout.clear(dc);

        // Title
        Layout.centerText(dc, 0.13, Graphics.FONT_TINY, Theme.ACCENT, "TODAY");
        Layout.centerText(dc, 0.22, Graphics.FONT_MEDIUM, Theme.FG, _c.session.name);

        // Blocks list (name + exercise count), spaced relative to screen height.
        var blocks = _c.session.blocks;
        var top = 0.36;
        var step = 0.11;
        for (var i = 0; i < blocks.size(); i++) {
            var b = blocks[i];
            var line = b.name + "  (" + b.exercises.size() + ")";
            Layout.centerText(dc, top + i * step, Graphics.FONT_XTINY, Theme.DIM, line);
        }

        // Estimated duration
        var est = "~" + Layout.fmtClock(_c.estimatedSeconds());
        Layout.centerText(dc, 0.74, Graphics.FONT_SMALL, Theme.FG, est);

        // Start hint adapts to the device's actual input mode at runtime.
        var hint = Layout.isTouch() ? "Tap to start" : "START";
        Layout.centerText(dc, 0.88, Graphics.FONT_TINY, Theme.ACCENT, hint);
    }

    // ----- Semantic actions (from ScreenDelegate) --------------------------
    function handleAction() {
        _c.start();
        return true;
    }

    function handleUp() {
        return false;
    }

    function handleDown() {
        return false;
    }

    // Back from the recap exits the app (default behavior).
    function handleCancel() {
        return false;
    }
}
