using Toybox.Application;
using Toybox.WatchUi;

// App entry point. Shows a loading screen first; it asynchronously fetches the
// day's session through the data layer (network -> offline cache -> mock) and
// then switches to the recap. No network is touched once the workout starts.
class GarminCalisthenicApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() {
        var controller = new WorkoutController();
        var view = new LoadingView(controller);
        return [view, new ScreenDelegate(view)];
    }
}
