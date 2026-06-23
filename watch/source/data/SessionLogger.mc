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

    // Build the upload payload's `results` array from the locally stored log for
    // a finished session: maps each validated set onto the server contract,
    // translating actual_* -> achieved_* and deriving `completed`. One entry per
    // set. Returns [] if nothing was logged (so the caller can skip the upload).
    function resultsForUpload(sessionId) {
        var results = [];
        var log = Storage.getValue("log:" + sessionId);
        if (log == null) {
            return results;
        }
        var arr = log as Lang.Array;
        for (var i = 0; i < arr.size(); i++) {
            var e = arr[i] as Lang.Dictionary;
            var targetReps = e.get("target_reps");
            var targetHold = e.get("target_hold_seconds");
            var achievedReps = e.get("actual_reps");
            var achievedHold = e.get("actual_hold_seconds");
            results.add({
                "exercise" => e.get("exercise"),
                "target_reps" => targetReps,
                "target_hold_seconds" => targetHold,
                "achieved_reps" => achievedReps,
                "achieved_hold_seconds" => achievedHold,
                "completed" => deriveCompleted(targetReps, achievedReps, targetHold, achievedHold)
            });
        }
        return results;
    }

    // A set counts as completed when the athlete met the target: held at least
    // as long as asked (isometric), or hit at least the target reps. A
    // "to-failure" set (target_reps == null) counts as completed as soon as any
    // reps were logged — there is no number to fall short of.
    private function deriveCompleted(targetReps, achievedReps, targetHold, achievedHold) {
        if (targetHold != null && targetHold > 0) {
            return achievedHold != null && achievedHold >= targetHold;
        }
        if (targetReps == null) {
            return achievedReps != null;
        }
        return achievedReps != null && achievedReps >= targetReps;
    }
}
