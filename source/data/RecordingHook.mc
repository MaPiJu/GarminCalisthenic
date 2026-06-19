using Toybox.ActivityRecording;

// ---------------------------------------------------------------------------
// REAL implementation of the optional parallel HR ActivityRecording feature.
//
// Compiled on high-memory devices only. On constrained devices (Enduro 2,
// Instinct 3 Solar/MIP) the jungle excludes (:hrRecording) and compiles the
// no-op stub in RecordingHookStub.mc instead — same API, zero footprint.
//
// The core workout flow only ever calls RecordingHook.start()/stop(), so it is
// completely decoupled from whether recording exists on a given device.
//
// NOTE: actually persisting a FIT recording also requires an activity-record
// permission in the manifest. It is intentionally left off for now so plain
// base-flow testing produces no save prompts; createSession is guarded and
// wrapped, so without the permission this simply no-ops at runtime.
// ---------------------------------------------------------------------------

(:hrRecording)
module RecordingHook {

    var _session = null;

    function start(name) {
        if (Toybox has :ActivityRecording) {
            try {
                _session = ActivityRecording.createSession({
                    :name => name,
                    :sport => ActivityRecording.SPORT_TRAINING
                });
                _session.start();
            } catch (ex) {
                // No permission / not supported: degrade silently, core flow continues.
                _session = null;
            }
        }
    }

    function stop(save) {
        if (_session != null) {
            try {
                _session.stop();
                if (save) {
                    _session.save();
                } else {
                    _session.discard();
                }
            } catch (ex) {
            }
            _session = null;
        }
    }
}
