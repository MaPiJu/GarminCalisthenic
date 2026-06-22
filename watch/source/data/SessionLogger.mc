using Toybox.Application.Storage;
using Toybox.Lang;
using Toybox.Time;

// ---------------------------------------------------------------------------
// Local-first logging. Every validated set is written to Application.Storage
// immediately, so a workout never depends on connectivity. A later session of
// the companion app can read/upload these keys.
//
// Storage layout:
//   "log:<session_id>"  -> Array<Dictionary> (one entry per validated set)
//   "last_summary"      -> Dictionary (most recent finished-session summary)
// ---------------------------------------------------------------------------

class SessionLogger {

    private var _logKey;

    function initialize() {
    }

    function beginSession(session) {
        _logKey = "log:" + session.id;
        // Start a fresh log for this session run.
        Storage.setValue(_logKey, []);
    }

    // Append one validated set. Either actualReps or actualHoldSeconds is set,
    // depending on the exercise type; the other stays null.
    function logSet(sessionId, blockName, exercise, setIndex, actualReps, actualHoldSeconds) {
        var entry = {
            "ts" => Time.now().value(),
            "block" => blockName,
            "exercise" => exercise.name,
            "set" => setIndex,
            "target_reps" => exercise.targetReps,
            "actual_reps" => actualReps,
            "target_hold_seconds" => exercise.targetHoldSeconds,
            "actual_hold_seconds" => actualHoldSeconds
        };

        var log = Storage.getValue(_logKey);
        if (log == null) {
            log = [];
        }
        (log as Lang.Array).add(entry);
        // Write back after every set — durable immediately.
        Storage.setValue(_logKey, log);
    }

    function endSession(session, completedSets, totalSets, totalReps, elapsedSeconds) {
        Storage.setValue("last_summary", {
            "session_id" => session.id,
            "session_name" => session.name,
            "completed_sets" => completedSets,
            "total_sets" => totalSets,
            "total_reps" => totalReps,
            "elapsed_seconds" => elapsedSeconds,
            "finished_at" => Time.now().value()
        });
    }
}
