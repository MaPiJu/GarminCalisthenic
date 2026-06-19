using Toybox.Application;

// ---------------------------------------------------------------------------
// Data-access layer. The UI only ever asks the repository for a Session; it
// has no idea whether the bytes came from a bundled resource or the network.
//
// TODAY: loads the bundled mock JSON resource.
// LATER: a single grouped Communications.makeWebRequest per session will fetch
//        the same Dictionary shape; only loadSession() changes, parseSession()
//        and the model stay identical. A sketch of that path is left below.
// ---------------------------------------------------------------------------

class SessionRepository {

    function initialize() {
    }

    // Synchronous load of the mock session (no network during the workout).
    function loadSession() {
        var dict = Application.loadResource(Rez.JsonData.MockSession);
        return parseSession(dict);
    }

    // ---- Future network path (kept here to show the seam is trivial) -------
    //
    // function fetchSession(callback) {
    //     Communications.makeWebRequest(
    //         url,
    //         params,
    //         { :method => Communications.HTTP_REQUEST_METHOD_GET,
    //           :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON },
    //         method(:onSessionReceived));
    //     // onSessionReceived(code, data) { callback.invoke(parseSession(data)); }
    // }
}
