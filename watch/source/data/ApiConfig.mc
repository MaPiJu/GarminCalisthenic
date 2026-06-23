using Toybox.Application.Storage;

// ---------------------------------------------------------------------------
// Backend API contract + connection config.
//
// This watch brick is ONLY the client. The server (the service that calls the
// Claude API to generate/adapt the session) is a separate brick and is out of
// scope here — but its contract is frozen below so the two sides agree.
//
//   API CONTRACT
//   ------------
//   GET  {BASE_URL}/sessions/today?user_id=<id>
//   Headers:
//     Authorization: Bearer <token>
//     Accept: application/json
//   Response 200 application/json — EXACTLY the mock_session.json shape:
//     {
//       "session_id":   string,
//       "session_name": string,
//       "blocks": [
//         { "block_name": string,
//           "exercises": [
//             { "name": string,
//               "sets": number,
//               "target_reps": number|null,
//               "target_hold_seconds": number|null,
//               "rest_seconds": number } ] } ]
//     }
//   Any non-200 (or transport error / timeout) -> the client falls back to the
//   last session cached in Storage, then to the bundled mock (see
//   SessionRepository). The network is touched ONLY before the workout starts.
//
//   POST {BASE_URL}/sessions/log
//   Headers:
//     Authorization: Bearer <token>
//     Content-Type: application/json
//   Body (what the athlete actually did; one entry per validated set):
//     {
//       "user_id":    string,
//       "session_id": string,
//       "results": [
//         { "exercise":             string,
//           "target_reps":          number|null,
//           "target_hold_seconds":  number|null,
//           "achieved_reps":        number|null,
//           "achieved_hold_seconds":number|null,
//           "completed":            boolean } ]
//     }
//   Response 200 application/json: { "ok": true }. Uploaded AFTER the workout
//   (never during it): queued locally and flushed when online (see LogUploader).
//
// Identity / auth are provisioned locally (e.g. by the future companion app at
// pairing time) and read from Storage, with dev placeholders so the app runs
// stand-alone today.
// ---------------------------------------------------------------------------

module ApiConfig {

    // TODO(backend brick): point at the real host once the server exists.
    const BASE_URL = "https://api.example.com/v1";

    // How long we wait for the session before giving up and going offline.
    // Kept short on purpose: a stale-but-cached plan beats a long stall.
    const REQUEST_TIMEOUT_MS = 8000;

    // Storage keys shared with the companion-provisioning path.
    const KEY_USER_ID    = "user_id";
    const KEY_AUTH_TOKEN = "auth_token";

    // Athlete identifier sent to the backend. Provisioned locally; dev default
    // keeps the app usable before any pairing has happened.
    function userId() {
        var id = Storage.getValue(KEY_USER_ID);
        return id != null ? id : "demo-user";
    }

    // Bearer token provisioned locally. Dev default is a harmless placeholder.
    function authToken() {
        var token = Storage.getValue(KEY_AUTH_TOKEN);
        return token != null ? token : "DEV_TOKEN";
    }

    // Full URL for "today's session" for the current athlete.
    function sessionUrl() {
        return BASE_URL + "/sessions/today";
    }

    // Full URL for uploading what was actually done after a workout.
    function logUrl() {
        return BASE_URL + "/sessions/log";
    }

    // Query parameters for the grouped per-session GET.
    function requestParams() {
        return { "user_id" => userId() };
    }

    // Request headers for the GET (auth + content negotiation).
    function headers() {
        return {
            "Authorization" => "Bearer " + authToken(),
            "Accept" => "application/json"
        };
    }

    // Request headers for the log POST (auth + JSON body). The JSON content
    // type makes makeWebRequest serialize the params Dictionary as a JSON body.
    function uploadHeaders() {
        return {
            "Authorization" => "Bearer " + authToken(),
            "Content-Type" => "application/json"
        };
    }
}
