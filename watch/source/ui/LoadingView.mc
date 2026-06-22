using Toybox.WatchUi;
using Toybox.Graphics;

// ---------------------------------------------------------------------------
// First screen shown while the day's session is fetched asynchronously (one
// grouped web request, before the workout). It kicks off the load on first
// show, then the controller switches us out to the Summary as soon as a session
// is available — whether from the network, the offline cache, or the mock.
//
// Only a HARD failure (no network AND no cache AND no bundled mock — practically
// impossible) stays here, showing a retry affordance.
// ---------------------------------------------------------------------------
class LoadingView extends WatchUi.View {

    private var _c;        // WorkoutController
    private var _started;  // load kicked off only once per show cycle
    private var _failed;   // hard failure -> show retry

    function initialize(controller) {
        View.initialize();
        _c = controller;
        _started = false;
        _failed = false;
    }

    function onShow() {
        if (!_started) {
            _started = true;
            _c.beginLoad(self);
        }
    }

    // ----- Callbacks from the controller -----------------------------------
    function onLoadStarted() {
        _failed = false;
        WatchUi.requestUpdate();
    }

    function onLoadFailed() {
        _failed = true;
        WatchUi.requestUpdate();
    }

    function onUpdate(dc) {
        Layout.clear(dc);
        if (_failed) {
            Layout.centerText(dc, 0.36, Graphics.FONT_SMALL, Theme.WARN, "No session");
            Layout.centerText(dc, 0.50, Graphics.FONT_XTINY, Theme.DIM, "Check connection");
            Layout.centerText(dc, 0.74, Graphics.FONT_TINY, Theme.ACCENT,
                Layout.isTouch() ? "Tap to retry" : "START: retry");
        } else {
            Layout.centerText(dc, 0.42, Graphics.FONT_MEDIUM, Theme.FG, "Loading");
            Layout.centerText(dc, 0.56, Graphics.FONT_XTINY, Theme.DIM, "today's session");
        }
    }

    // ----- Semantic actions (from ScreenDelegate) --------------------------
    function handleAction() {
        if (_failed) {
            _c.retryLoad();
        }
        return true;
    }

    function handleUp() {
        return false;
    }

    function handleDown() {
        return false;
    }

    // Back during loading exits the app (default behavior).
    function handleCancel() {
        return false;
    }
}
