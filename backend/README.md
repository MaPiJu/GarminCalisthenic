# backend — session generation service (not built yet)

The "coach IA" brick of the monorepo. A service that, per athlete, calls the
Claude API to generate or adapt a calisthenics session and returns it as the
JSON contract the watch already consumes.

This folder is currently a placeholder. The watch app does **not** depend on it
to run (it falls back to a cached session, then to a bundled mock), so the
backend can be built independently.

## Responsibility

Expose exactly one endpoint the watch calls once, before a workout:

```
GET {BASE_URL}/sessions/today?user_id=<id>
Headers:
  Authorization: Bearer <token>
  Accept: application/json
```

Respond `200 application/json` with the **frozen contract** (identical to
`watch/resources/json/mock_session.json` and to `ApiConfig.mc` on the watch):

```json
{
  "session_id": "string",
  "session_name": "string",
  "blocks": [
    {
      "block_name": "string",
      "exercises": [
        {
          "name": "string",
          "sets": 0,
          "target_reps": 0,
          "target_hold_seconds": null,
          "rest_seconds": 0
        }
      ]
    }
  ]
}
```

Rules:
- `target_hold_seconds != null && > 0` ⇒ isometric hold; otherwise reps.
- `target_reps` may be `null` (= "to failure", the athlete enters the count).
- Numbers are plain JSON numbers; `rest_seconds` is seconds.

## Hard requirements (from the watch client)

- **HTTPS only** — Garmin's `Communications.makeWebRequest` refuses plain HTTP.
- Honor the `Authorization: Bearer <token>` header (token + `user_id` are
  provisioned on the watch via `Storage`, see `watch/source/data/ApiConfig.mc`).
- Keep latency reasonable: the watch gives up after
  `ApiConfig.REQUEST_TIMEOUT_MS` (8s) and goes offline.
- Generation (Claude API call) should ideally be precomputed/cached server-side
  so "today's session" returns fast; don't block the GET on a slow model call if
  it risks the 8s budget.

## Suggested shape (to decide when implementing)

- Runtime: Node (TS) or Python — TBD.
- The Claude API call lives entirely here; the watch never sees it.
- Store generated sessions keyed by `user_id` + date so repeated GETs are cheap
  and idempotent.

When this lands, flip `watch/source/data/ApiConfig.mc` `BASE_URL` to the real
host and provision `user_id` / `auth_token` on the device.
