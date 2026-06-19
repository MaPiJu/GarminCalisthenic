using Toybox.Application;
using Toybox.WatchUi;

// App entry point. Loads the session through the data layer, then shows the
// recap screen as the initial view.
class GarminCalisthenicApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() {
        var controller = new WorkoutController();
        controller.load();
        var view = new SummaryView(controller);
        return [view, new ScreenDelegate(view)];
    }
}
