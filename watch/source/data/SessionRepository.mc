using Toybox.Application;
using Toybox.Application.Storage;
using Toybox.Communications;
using Toybox.Timer;

// ---------------------------------------------------------------------------
// Data-access layer. The UI only ever asks the repository for a Session; it has
// no idea whether the bytes came from the network, the offline cache, or the
// bundled mock. parseSession() and the models are identical for all three
// because every source yields the same Dictionary shape (the JSON contract).
//
// fetchSession() does ONE grouped Communications.makeWebRequest per session,
// BEFORE the workout starts. During the workout we never touch the network.
//
// Resilience ladder (each rung falls through to the next):
//   1. network 200  -> parse + cache the raw JSON for next time     (:ok)
//   2. error/timeout + cache present -> replay last cached session  (:offlineCache)
//   3. no cache yet -> bundled mock so the app is never dead         (:offlineMock)
//   4. nothing at all (should never happen) -> null + :error
// ---------------------------------------------------------------------------

class SessionRepository {

    // Raw last-good session JSON, kept for offline replay.
    private const CACHE_KEY = "cached_session_json";

    private var _callback;   // invoked as callback.invoke(statusSymbol, Session|null)
    private var _timer;      // explicit timeout guard
    private var _responded;  // ensures the callback fires exactly once

    function initialize() {
    }

    // Asynchronously fetch today's session. `callback` is a Method invoked once
    // with (status, session): status is one of :ok / :offlineCache /
    // :offlineMock / :error; session is null only for :error.
    function fetchSession(callback) {
        _callback = callback;
        _responded = false;

        // Guard timer: makeWebRequest has its own internal timeout, but we add
        // an explicit one so a never-returning request can't hang the loading
        // screen. Whichever fires first wins; _responded blocks the loser.
        _timer = new Timer.Timer();
        _timer.start(method(:onTimeout), ApiConfig.REQUEST_TIMEOUT_MS, false);

        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :headers => ApiConfig.headers(),
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
        try {
            Communications.makeWebRequest(
                ApiConfig.sessionUrl(),
                ApiConfig.requestParams(),
                options,
                method(:onReceive));
        } catch (ex) {
            // Synchronous throw (e.g. permission/setup issue): go offline now
            // instead of waiting out the guard timer.
            if (!_responded) {
                _responded = true;
                fallbackOffline();
            }
        }
    }

    // makeWebRequest response handler. A negative responseCode (no phone, BLE
    // timeout, etc.) or any non-200 lands in the offline fallback. The signature
    // must match Communications' callback PolyType exactly so the type checker
    // accepts method(:onReceive) as the request callback.
    function onReceive(
        responseCode as Toybox.Lang.Number,
        data as Null or Toybox.Lang.Dictionary or Toybox.Lang.String or Toybox.PersistedContent.Iterator
    ) as Void {
        if (_responded) {
            return;
        }
        _responded = true;
        cancelTimer();

        if (responseCode == 200 && data != null) {
            // Cache the raw dict so a later offline run can replay it verbatim.
            Storage.setValue(CACHE_KEY, data);
            _callback.invoke(:ok, parseSession(data));
        } else {
            fallbackOffline();
        }
    }

    // Explicit timeout fired before any response. Go offline; a late web
    // response will be ignored because _responded is now true.
    function onTimeout() as Void {
        if (_responded) {
            return;
        }
        _responded = true;
        fallbackOffline();
    }

    // Offline path: last cached session, else bundled mock, else hard error.
    private function fallbackOffline() {
        cancelTimer();

        var cached = Storage.getValue(CACHE_KEY);
        if (cached != null) {
            _callback.invoke(:offlineCache, parseSession(cached));
            return;
        }

        var mock = Application.loadResource(Rez.JsonData.MockSession);
        if (mock != null) {
            _callback.invoke(:offlineMock, parseSession(mock));
            return;
        }

        _callback.invoke(:error, null);
    }

    private function cancelTimer() {
        if (_timer != null) {
            _timer.stop();
            _timer = null;
        }
    }
}
