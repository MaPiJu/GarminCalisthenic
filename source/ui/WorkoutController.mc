using Toybox.WatchUi;
using Toybox.System;

// ---------------------------------------------------------------------------
// Owns the workout state machine and every view transition. Views are dumb:
// they render controller state and forward semantic actions back here.
//
// The exercises of all blocks are flattened into one ordered list for
// progression, while the original block grouping is preserved for the recap.
// ---------------------------------------------------------------------------

class WorkoutController {

    public var session;             // Session

    private var _logger;
    private var _flat;              // Array of [blockName, Exercise]
    private var _exIndex;          // index into _flat
    private var _setIndex;         // 1-based set within the current exercise
    private var _startMs;          // System timer at workout start

    public var totalSets;
    public var completedSets;
    public var totalReps;

    function initialize() {
        _logger = new SessionLogger();
        _exIndex = 0;
        _setIndex = 1;
        totalSets = 0;
        completedSets = 0;
        totalReps = 0;
    }

    // Load the session from the data layer (mock JSON today, network later).
    function load() {
        var repo = new SessionRepository();
        session = repo.loadSession();
        _flat = [];
        for (var b = 0; b < session.blocks.size(); b++) {
            var block = session.blocks[b];
            for (var e = 0; e < block.exercises.size(); e++) {
                _flat.add([block.name, block.exercises[e]]);
                totalSets += block.exercises[e].sets;
            }
        }
    }

    // ----- Accessors used by the views -------------------------------------
    function currentBlockName() {
        return _flat[_exIndex][0];
    }

    function currentExercise() {
        return _flat[_exIndex][1];
    }

    function currentSetIndex() {
        return _setIndex;
    }

    function exerciseCount() {
        return _flat.size();
    }

    function currentExerciseNumber() {
        return _exIndex + 1;
    }

    // Rough estimate for the recap screen: reps at ~3s each, holds at their
    // duration, plus rest between sets. Documented approximation, not exact.
    function estimatedSeconds() {
        var total = 0;
        for (var i = 0; i < _flat.size(); i++) {
            var ex = _flat[i][1];
            var perSet = ex.isHold() ? ex.targetHoldSeconds
                                     : (ex.targetReps != null ? ex.targetReps * 3 : 30);
            total += ex.sets * perSet;
            total += (ex.sets - 1) * ex.restSeconds; // rests between this exercise's sets
        }
        return total;
    }

    // ----- Lifecycle / transitions -----------------------------------------
    function start() {
        _startMs = System.getTimer();
        _logger.beginSession(session);
        RecordingHook.start("Calisthenics"); // no-op on constrained variants
        showExercise(WatchUi.SLIDE_LEFT);
    }

    function showExercise(transition) {
        var view = new ExerciseView(self);
        WatchUi.switchToView(view, new ScreenDelegate(view), transition);
    }

    function showHold() {
        var view = new HoldView(self);
        WatchUi.switchToView(view, new ScreenDelegate(view), WatchUi.SLIDE_LEFT);
    }

    function showRest(seconds) {
        var view = new RestView(self, seconds);
        WatchUi.switchToView(view, new ScreenDelegate(view), WatchUi.SLIDE_UP);
    }

    function showFinish() {
        RecordingHook.stop(true); // no-op on constrained variants
        var elapsed = (System.getTimer() - _startMs) / 1000;
        _logger.endSession(session, completedSets, totalSets, totalReps, elapsed);
        var view = new FinishView(self, elapsed);
        WatchUi.switchToView(view, new ScreenDelegate(view), WatchUi.SLIDE_UP);
    }

    // ----- Progression -----------------------------------------------------
    // Called when a set is validated. Logs it locally, then advances to the
    // rest timer / next set / finish as appropriate.
    function completeSet(actualReps, actualHoldSeconds) {
        var ex = currentExercise();
        var blockName = currentBlockName();
        var restSeconds = ex.restSeconds;

        _logger.logSet(session.id, blockName, ex, _setIndex, actualReps, actualHoldSeconds);
        completedSets += 1;
        if (actualReps != null) {
            totalReps += actualReps;
        }

        var hasMore = advancePointer();
        if (!hasMore) {
            showFinish();
        } else if (restSeconds != null && restSeconds > 0) {
            showRest(restSeconds);
        } else {
            showExercise(WatchUi.SLIDE_LEFT);
        }
    }

    // Move the pointer to the next set/exercise. Returns false when the whole
    // session is done.
    private function advancePointer() {
        _setIndex += 1;
        if (_setIndex > currentExercise().sets) {
            _exIndex += 1;
            _setIndex = 1;
            if (_exIndex >= _flat.size()) {
                return false;
            }
        }
        return true;
    }

    // Rest timer finished (or was skipped) -> show the next set.
    function onRestDone() {
        showExercise(WatchUi.SLIDE_LEFT);
    }
}
