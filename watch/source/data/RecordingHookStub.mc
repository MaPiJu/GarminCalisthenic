// ---------------------------------------------------------------------------
// NO-OP stub of the optional HR ActivityRecording feature.
//
// Compiled on constrained devices (jungle excludes (:noHrRecording) everywhere
// else). Exposes the exact same RecordingHook API as the real module so the
// core flow links unchanged and uses no recording memory on these devices.
// ---------------------------------------------------------------------------

(:noHrRecording)
module RecordingHook {

    function start(name) {
    }

    function stop(save) {
    }
}
