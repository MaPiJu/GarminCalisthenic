using Toybox.Application.Storage;
using Toybox.Communications;
using Toybox.Lang;
using Toybox.Timer;

// ---------------------------------------------------------------------------
// Watch -> server upload of what was actually done (POST /sessions/log).
//
// The workout itself never touches the network: every set is logged locally and
// immediately (SessionLogger). This class takes over AFTER the workout — it
// builds nothing itself, it just persists a ready-made payload and ships it.
//
// Store-and-forward: a finished session's results are appended to a small
// durable queue in Storage, then flushed. "Send when online" falls out for
// free — flush() is also called at app launch, so anything that couldn't go out
// last time (no phone / BLE / server down) is retried on the next connected run.
//
// One request in flight at a time (sequential drain), with the same timeout-
// guard + fire-once discipline as SessionRepository. Dequeue policy:
//   - 200          -> server stored it: drop from queue, send the next.
//   - 400 / 401    -> the payload itself is the problem (malformed body / bad
//                     token); retrying can't help, so drop it (one poison item
//                     can't block the queue) and continue with the next.
//   - 5xx / other  -> server reached but the failure is transient (server
//                     error, or a 404 from a down/misrouted backend): KEEP it
//                     queued, stop, and retry on a later flush.
//   - transport error / timeout (no phone, BLE, host unreachable) -> KEEP it
//                     queued, stop, retry on a later flush (genuinely offline).
// ---------------------------------------------------------------------------

class LogUploader {

    private const QUEUE_KEY = "upload_queue";
    private const MAX_QUEUE = 10;   // bound growth if we stay offline for a while

    private var _timer;       // explicit per-request timeout guard
    private var _responded;   // ensures each request resolves exactly once
    private var _inFlight;    // the payload currently being POSTed (null = idle)

    function initialize() {
        _inFlight = null;
    }

    // Queue a finished session's results for upload. Self-contained (carries the
    // user id), so flush() needs nothing else. Re-finishing the same session
    // replaces its pending entry instead of duplicating it; the queue is bounded.
    function enqueue(userId, sessionId, results) {
        if (results == null || (results as Lang.Array).size() == 0) {
            return; // nothing logged -> nothing to upload
        }
        var payload = {
            "user_id" => userId,
            "session_id" => sessionId,
            "results" => results
        };
        var queue = pruneForSession(sessionId) as Lang.Array;
        queue.add(payload);
        while (queue.size() > MAX_QUEUE) {
            queue.remove(queue[0]); // drop the oldest
        }
        Storage.setValue(QUEUE_KEY, queue);
    }

    // Try to drain the queue. No-op if a request is already in flight or the
    // queue is empty. Safe to call at app launch and after each finish.
    function flush() {
        if (_inFlight != null) {
            return;
        }
        sendNext();
    }

    // ----- internals -------------------------------------------------------
    private function sendNext() {
        var queue = Storage.getValue(QUEUE_KEY);
        if (queue == null) {
            _inFlight = null;
            return;
        }
        var arr = queue as Lang.Array;
        if (arr.size() == 0) {
            _inFlight = null;
            return;
        }

        _inFlight = arr[0] as Lang.Dictionary;
        _responded = false;

        _timer = new Timer.Timer();
        _timer.start(method(:onTimeout), ApiConfig.REQUEST_TIMEOUT_MS, false);

        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_POST,
            :headers => ApiConfig.uploadHeaders(),
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
        try {
            Communications.makeWebRequest(
                ApiConfig.logUrl(),
                _inFlight,
                options,
                method(:onReceive));
        } catch (ex) {
            // Synchronous throw (permission/setup): treat as transport failure —
            // keep the item queued and stop; a later flush will retry.
            cancelTimer();
            _inFlight = null;
        }
    }

    // makeWebRequest response handler. Signature must match Communications'
    // callback PolyType exactly so the type checker accepts method(:onReceive).
    function onReceive(
        responseCode as Toybox.Lang.Number,
        data as Null or Toybox.Lang.Dictionary or Toybox.Lang.String or Toybox.PersistedContent.Iterator
    ) as Void {
        if (_responded) {
            return;
        }
        _responded = true;
        cancelTimer();

        if (responseCode == 200) {
            // Stored server-side: drop it and continue draining.
            removeFromQueue(_inFlight.get("session_id"));
            _inFlight = null;
            sendNext();
        } else if (responseCode == 400 || responseCode == 401) {
            // Client error: the payload itself is the problem (malformed body /
            // bad token). Retrying the identical item can't help and would block
            // the queue, so drop it and move on to the next one.
            removeFromQueue(_inFlight.get("session_id"));
            _inFlight = null;
            sendNext();
        } else {
            // Everything else is transient/recoverable: a server error (5xx), a
            // 404 from a down/misrouted backend, or a negative transport/timeout
            // code (no phone / BLE / host unreachable). Keep it queued and stop;
            // a later flush (e.g. app launch) retries it. True store-and-forward.
            _inFlight = null;
        }
    }

    // Guard timer fired before any response: treat as offline, keep queued.
    function onTimeout() as Void {
        if (_responded) {
            return;
        }
        _responded = true;
        _inFlight = null;
    }

    // Return the queue with any existing entry for `sessionId` removed (so a
    // re-finish replaces rather than duplicates). Always returns a fresh Array.
    private function pruneForSession(sessionId) {
        var queue = Storage.getValue(QUEUE_KEY);
        var kept = [];
        if (queue != null) {
            var arr = queue as Lang.Array;
            for (var i = 0; i < arr.size(); i++) {
                var item = arr[i] as Lang.Dictionary;
                // Compare by VALUE: item.get(...) is statically Object, so the
                // != operator would do identity comparison and never match (the
                // queue would never shrink -> no dedup, infinite resend loop).
                var sid = item.get("session_id");
                if (sid == null || !(sid as Lang.String).equals(sessionId)) {
                    kept.add(item);
                }
            }
        }
        return kept;
    }

    private function removeFromQueue(sessionId) {
        Storage.setValue(QUEUE_KEY, pruneForSession(sessionId));
    }

    private function cancelTimer() {
        if (_timer != null) {
            _timer.stop();
            _timer = null;
        }
    }
}
