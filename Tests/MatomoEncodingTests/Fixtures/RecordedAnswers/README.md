# Recorded Matomo answers

These are the answers a self-hosted Matomo gave to bulk tracking requests on 2026-11-28.
`MatomoRecordedAnswerTests` runs each one through `MatomoBatchEncoder.outcome(of:for:)`, or
through `HTTPDestination` for an answer that isn't a 2xx.

## What answered

- Images: `matomo:6.0.0-apache`
  (`sha256:0b2bc08d184e8d9adc612eaa3456e19de61b04666b757c38ae110e07871f5a23`), which is Matomo
  6.0.0 on Apache 2.4.71 and PHP 8.4.28, and `mariadb:11.8.10`
  (`sha256:73c35e8483b56390cc98f8d6d9840244bd03c929aea7109490641b9389a18088`).
- QueuedTracking 6.0.5, from its GitHub release
  (`github.com/matomo-org/plugin-QueuedTracking/archive/refs/tags/6.0.5.tar.gz`, SHA-256
  `42380eeac417f35aae0f122d8ec58e36c21e3c31c62946e474c4d024f971b4c0`). It was copied into
  `plugins/` and turned on with `./console plugin:activate QueuedTracking`. Installing it
  fetched nothing else: the plugin ships its Redis client in `libs/`, and the MySQL backend
  needs no extra service.
- Both containers were on an internal Docker network with no route out. Every request was made
  from inside the Matomo container to `http://localhost/matomo.php`. `enable_internet_features`
  was set to 0, and the installer's GeoIP and newsletter options were left off.
- The installation was made through the web installer. It had a throwaway super user and one
  site, ID 1, in UTC. Every setting not named below kept its default. In particular,
  `bulk_requests_require_authentication` was 0 and `record_statistics` was 1.

## The requests

Each request was `POST /matomo.php` with `Content-Type: application/json`, sent with
`curl --data-binary`. Its body is the file of the same name under `requests/`, exactly as sent.
The bodies have the shape `MatomoBatchEncoder` writes, with no `token_auth`, and the encoder
writes `requests/valid.json` byte for byte (`recordedRequestIsTheEncoders`). Each `cdt` is
seconds before the time the request was sent, so it falls inside Matomo's 24 hours, except
where noted.

| Request | Holds |
|---|---|
| `valid` | Three events of one visitor for site 1 |
| `unknown-site` | The same three events for site 99, which doesn't exist |
| `mixed-sites` | One event for site 1 and one for site 99 |
| `stale-timestamp` | One event for site 1 with a `cdt` two days old |
| `bad-token` | `valid`'s three events, with a `token_auth` of 32 random hexadecimal digits that belongs to no user. The fixture's value is replaced with `REDACTED`. |
| `malformed` | `{"requests":"?idsite=1&rec=1"}`: `requests` is a string, not an array |

## The answers

Each directory is one server setup. In each directory, `<request>.headers` holds the status line
and headers as curl's `-D` wrote them, and `<request>.body` holds the body as it was received.

| Directory | Setup |
|---|---|
| `queue-off` | QueuedTracking installed, its queue off |
| `queue-on` | Queue on, MySQL backend, other settings at their defaults: 25 requests to process, processed during tracking requests. The 12 tracking requests stayed queued. |
| `queue-on-processing` | As `queue-on`, with 1 request to process, so each tracking request processes the queue after Matomo has answered it |
| `queue-off-record-statistics-0` | Queue off, `[Tracker] record_statistics = 0` |
| `queue-off-require-authentication` | Queue off, `[Tracker] bulk_requests_require_authentication = 1` |

| Answer | Status | Body |
|---|---|---|
| `queue-off/valid` | 200 | `{"status":"success","tracked":3,"invalid":0}` |
| `queue-off/unknown-site` | 200 | `{"status":"success","tracked":0,"invalid":3}` |
| `queue-off/mixed-sites` | 200 | `{"status":"success","tracked":1,"invalid":1}` |
| `queue-off/stale-timestamp` | 200 | `{"status":"success","tracked":0,"invalid":1}` |
| `queue-off/bad-token` | 200 | `{"status":"success","tracked":3,"invalid":0}` |
| `queue-off/malformed` | 400 | `{"status":"error","tracked":0,"invalid":0}` |
| `queue-off-record-statistics-0/valid` | 200 | `{"status":"success","tracked":0,"invalid":0}` |
| `queue-off-require-authentication/valid` | 401 | `{"status":"error","tracked":0,"invalid":0}` |
| `queue-on/*`, `queue-on-processing/*` | 200, or 400 for `malformed` | A 43-byte transparent GIF, `Content-Type: image/gif` |

With the queue off, `tracked` counted what Matomo stored: the site's `log_link_visit_action`
rows grew by 3 for `valid`, 3 for `bad-token` and 1 for `mixed-sites`. With the queue on,
Matomo answered every request with the same GIF before it checked any tracking request.
`queuedtracking:process` later stored the 7 valid ones and dropped the 5 for site 99 or with
the stale `cdt`, and nothing reported the dropped ones.
