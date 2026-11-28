# Choosing Destinations

Deliver events to your logs, your traces, a server or memory, and decide what each destination may see.

## Overview

A `Destination` is a plain sink: `deliver(to:)` hands it each batch of records. Traffluent ships a
few, each in a module of its own, so an app links only the ones it uses.

### Logs and traces

To see events beside your logs or traces, deliver to `LoggerDestination(logger:)` (module
``/LoggingDestinations``) or `SpanEventDestination(tracer:)` (module ``/TracingDestinations``).
Only apps that use swift-log or swift-distributed-tracing this way link them. A span event joins
the span that was active when the event was tracked, even if delivery runs later.

### A server

To send batches to a server, deliver to `HTTPDestination(endpoint:headerFields:encoder:)` (module
``/HTTPDestinations``). It posts each batch as one request whose body is what your `BatchEncoder`
writes for it, so events need no `Codable` conformance and the wire format is yours. It sends with
`URLSession` by default, or through any `HTTPTransport` you pass as `transport:`.

A send that gets no response, or a 5xx, 408 or 429 status, is sent again after a wait, until it is
answered with 2xx. So is one answered with a status your encoder lists in its
`transientStatuses`, for a server that answers another failure to a request worth sending again.
Your encoder's `outcome(of:for:)` reads each 2xx answer's body: return `.delivered` for a server
that stores whatever it answers 2xx to, `.rejected(reason:)` for an answer that says nothing was
stored, which the destination drops and reports as `HTTPDropReport.rejectedInBody`, or
`.transient(reason:)` for one worth sending again, which it retries like a 5xx.
The nominal waits start at 1 second and double up to 60 seconds, and each wait is a random one
shorter than that (full jitter), so apps refused at the same moment don't all retry at the same
moment. Pass an `ExponentialBackoff` as `backoff:` for other waits, `jitter: .none` for the nominal
ones, and in tests a test clock as `clock:` and a seeded generator as `randomNumberGenerator:`. The
destination takes the next batch only once this one arrives, so a tracker's store keeps its records
until then, and a batch still being retried when the app ends is sent again on the next launch.
Other destinations aren't held up.

Meanwhile the delivery's later batches wait in this destination's buffer of `batchBufferLimit`
batches, which drops its oldest when full. With a store, the records of a dropped batch aren't
lost: once the destination has caught up, the delivery reads them back from the store and sends
them to that destination alone, in the same run. They keep their context (session, screen, sample
rate and trace), which the delivery holds on to while the events wait in the store. A destination
so far behind that more than ten buffers' worth of its batches are dropped gets the oldest of them
on the next launch instead. Without a store, a dropped batch's records are gone, so give the
tracker a store if the app may be offline for long (<doc:PersistingRecords>). To hear about each
drop, read the delivery's `bufferDropReports`:

```swift
let delivery = tracker.records.batch().deliver(to: collector)
let bufferDrops = delivery.bufferDropReports
let watching = Task {
    for await drop in bufferDrops where drop.storedRecordCount < drop.recordCount {
        print("Lost \(drop.recordCount - drop.storedRecordCount) events tracked from \(drop.timestamps.lowerBound)")
    }
}
```

A report names the destination by its place in `deliver(to:)`'s list, counting from 0. It also
gives how many records were dropped, when they were tracked, and how many of them a store keeps
to send again. Drops no one has read yet merge into one report per destination, so a report may
count several batches. The delivery logs each drop too. Its reports end once the delivery is
gone, and a delivery built to replace one has reports of its own. One task reads them at a time,
as with every report stream the library hands out: a second reader waits its turn.

An app that builds a new delivery each time one stops, to restart it after a failure or as it
returns to the foreground, forwards each delivery's reports into one queue of its own, an
`AsyncQueue` it writes through `AsyncQueue.Continuation`, and reads that queue in one place. Hand
the queue each delivery's `bufferDropReports` as the delivery starts, and read each in a task of a
task group, so the queue ends only once every delivery's reports have.

Some batches won't succeed if sent again, so they are dropped: one the endpoint answers with any
other status, one whose request the transport can never send (a malformed URL, a scheme it doesn't
support, or an `http` URL that App Transport Security refuses), and one the encoder can't encode.
The destination logs each at error level and reports it on `dropReports`, with the records'
identifiers and the status, the transport's reason or the encoder's error. Cancelling the delivery
stops the retries.

A request can carry a deadline, the latest time it may be sent, which an encoder sets for a vendor
that misdates or ignores events past some age while still answering 2xx. The destination reads its
`now:` clock before every attempt, the first included, and once the deadline has passed it stops
sending the request and reports it as `HTTPDropReport.deadlineExceeded(deadline:recordIDs:)`. The
Google Analytics, Matomo, Aptabase and Mixpanel encoders set one; a request without one is retried
for as long as it takes.

The bootstrapped tracing instrument, or the one you pass as `instrument:`, injects the trace
context of each request's first record into its header fields, so a server that extracts it joins
the request to the app's trace. The encoder's `Content-Type` always wins, and with no instrument
bootstrapped no header is added. Only the first record's context travels in the header fields;
write each record's context into the body if the server needs it.

To send to a self-hosted TraffluentCollector, give `HTTPDestination` a
`CollectorBatchEncoder(plan:)` (module ``/CollectorEncoding``) as its encoder, and the collector's
API key as an `Authorization: Bearer` header field. It writes the collector's ingest format: each
record's identifier (which a redelivered record keeps), its name, timestamp and redelivery marker,
its properties read through the event's schema in your `TrackingPlan`, and its standard context and
trace context. A `Sensitive` value is sent only while the record reveals it.

A record the encoder can't write is left out of the request, and the rest of its batch is sent.
That happens when the plan has no schema for the record's event at its version (an event that
conforms to `Event` by hand, left out of a list-free `TrackingPlan()`), when the event isn't
`Encodable`, when a value has no JSON form, such as a NaN, or when the record's timestamp has no
ISO 8601 form (NaN, infinite, or more than `Int64.max` milliseconds from 1970, as a faulty clock
can return). The destination logs each skipped record at error level and reports it on
`dropReports` as `HTTPDropReport.skipped(_:)`. A batch with no record the encoder can write sends
nothing.

### Vendors

Each analytics vendor Traffluent sends to has a module of its own, which `import Traffluent` leaves
out, holding a factory on `HTTPDestination` that makes a destination for it in one throwing call.
The factory checks what you pass it, fills in the vendor's endpoint, encoder and batch limits,
and leaves the rest to `HTTPDestination` as above: it retries and drops a vendor's requests as it
does any server's. Each module writes to the vendor's
public HTTP ingestion API, so no vendor SDK is linked.

| Vendor | Module | Factory | What the vendor receives |
|---|---|---|---|
| PostHog | ``/PostHogEncoding`` | `HTTPDestination.postHog(projectToken:host:plan:)` | Each record as an anonymous event: its session as `distinct_id` and `$session_id`, its identifier as `uuid`, its properties through your plan, and the standard context as PostHog's `$`-prefixed properties |
| Amplitude | ``/AmplitudeEncoding`` | `HTTPDestination.amplitude(apiKey:region:plan:)` | Each record as an event of an anonymous device: its session as `device_id`, the session's start as `session_id`, its identifier as `insert_id`, its time in epoch milliseconds, its properties through your plan as `event_properties`, and the standard context as Amplitude's own fields; no `user_id` |
| Mixpanel | ``/MixpanelEncoding`` | `HTTPDestination.mixpanel(projectToken:region:plan:)` | Each record as an event of an anonymous user: its session as `distinct_id` and `$device_id`, its identifier as `$insert_id`, its time in epoch milliseconds, its properties through your plan, the standard context as Mixpanel's default properties, and `ip` as `0`; no `$user_id` |
| Segment | ``/SegmentSpecEncoding`` | `HTTPDestination.segment(writeKey:region:plan:)` | Each record as a Segment-spec track call of an anonymous user: its session as `anonymousId`, its identifier as `messageId`, its time in ISO 8601, its properties through your plan, the standard context in the spec's `context` fields, and `context.ip` as `0.0.0.0`; no `userId`, `identify` or traits |
| RudderStack | ``/SegmentSpecEncoding`` | `HTTPDestination.rudderStack(writeKey:dataPlane:plan:)` | The same track calls as Segment, at your data plane, with `request_ip` as `0.0.0.0` too |
| Customer.io Data Pipelines | ``/SegmentSpecEncoding`` | `HTTPDestination.customerIO(apiKey:region:plan:)` | The same track calls as Segment, in strict mode |
| Google Analytics 4 (from a server) | ``/GoogleAnalyticsEncoding`` | `HTTPDestination.googleAnalytics(measurementID:apiSecret:region:plan:)` | Each record as a Measurement Protocol event of an anonymous client: its session as `client_id`, the session's start as `session_id`, its time in microseconds, its properties through your plan as `params`, and ad consent as denied; no `user_id`, user properties or standard context. The factory takes the stream's API secret, so it builds for macOS and Linux alone and refuses a Mac app at run time. An app sends to TraffluentCollector instead, which forwards to Google Analytics (<doc:ChoosingDestinations#Google-Analytics>) |
| Snowplow | ``/SnowplowEncoding`` | `HTTPDestination.snowplow(collector:vendor:appID:plan:)` | Each record as a self-describing event whose schema, `iglu:<vendor>/<name>/jsonschema/<version>-0-0`, your plan's Iglu export writes: its session as `sid` and nothing else to identify it, its identifier as `eid`, its time in epoch milliseconds as `dtm` and `ttm`, its properties through your plan, and the standard context as Snowplow's `mobile_context` and `application` entities; no `duid`, `uid` or cookie, as every request carries `SP-Anonymous` |
| TelemetryDeck | ``/TelemetryDeckEncoding`` | `HTTPDestination.telemetryDeck(appID:namespace:testMode:plan:)` | Each record as an Ingest API v3 signal: its session, hashed with SHA-256, as `clientUser` and the session itself as `sessionID`, so user counts are session counts; its time in ISO 8601 as `receivedAt`, its properties through your plan, flattened to dotted names, the standard context as TelemetryDeck's built-in `TelemetryDeck.` parameters, and `isTestMode` as you pass it; no other identifier |
| Matomo | ``/MatomoEncoding`` | `HTTPDestination.matomo(url:siteID:dimensions:category:plan:)` | Each record as a Matomo event in a bulk tracking request: your category as `e_c` and its name as `e_a`, the last 64 bits of its session as the visitor `_id`, so visitors are sessions, its time in Unix seconds as `cdt`, its locale as `lang`, and the properties you map as numbered custom dimensions; no `uid`, `cid` or `token_auth`, so a record over 23 hours old is skipped |
| Heap | ``/HeapEncoding`` | `HTTPDestination.heap(appID:region:plan:)` | Each record as a custom event through Heap's server-side bulk track API: its session as `identity`, so users are sessions, its identifier as `idempotency_key`, its time in ISO 8601, and its properties through your plan, flattened to dotted names of strings and numbers; no `user_id`, `session_id`, API key or standard context. Heap's server-side API complements its SDKs: every user it makes has only server-side events, which Heap shows as hidden and doesn't sessionize, so confirm they appear in your charts |
| Aptabase | ``/AptabaseEncoding`` | `HTTPDestination.aptabase(appKey:host:isDebug:plan:)` | Each record as an event through Aptabase's events API, in its EU or US cloud by the app key's region or on your own server: its session as `sessionId` and nothing else to identify it, its time in ISO 8601, its properties through your plan, flattened to dotted names, the standard context as Aptabase's `systemProps`, and `isDebug` as you pass it. Aptabase counts users itself, from a daily hash of each request's IP address and `User-Agent`, and keeps no event's identifier, so a record sent twice counts twice |

To write a destination for a vendor not in the table, see <doc:WritingAVendorDestination>.

### PostHog

To send to PostHog, Cloud or self-hosted, make the destination with
`HTTPDestination.postHog(projectToken:host:plan:)` (module ``/PostHogEncoding``). It posts to the
host's `/batch/`, sends no trace context in the header fields, and splits each batch to PostHog's
request and event sizes. The project token goes in the body; it is public, like every PostHog
client's, so no header is needed. The factory throws `PostHogSetupError` for an empty token, a
personal API key (`phx_…`), which must never ship in an app, and a host that isn't a plain `https`
URL. The destination retries and reports drops as it does for any server, and a record sent again
keeps its `uuid`. A batch with no record the encoder can write, an empty one included, makes no
request.

```swift
let plan = try TrackingPlan()
let postHog = try HTTPDestination.postHog(
    projectToken: projectToken,
    host: postHogHost,  // https://us.i.posthog.com, https://eu.i.posthog.com or your own
    plan: plan)
let tracker = Tracker(enrichers: [.sessions()])
let delivery = tracker.records.batch().deliver(to: postHog)
```

Each event's `distinct_id` is the record's session (`Enricher.sessions()`), also sent as
`$session_id` so PostHog's session and web analytics group the events, and nothing else identifies
anyone. Events are sent as anonymous (`$process_person_profile: false`), and the vendor
identifier, trace context and your own context keys aren't sent. PostHog counts a person per `distinct_id`, so
its unique users are sessions. The encoder adds PostHog's own properties for the app, device,
operating system, locale and network when the standard context enrichers set them. Event names are
sent as they are.

PostHog rejects a whole batch with 400 when one of its events has no `distinct_id`, so every event
gets one. A record with no session, from a tracker without `.sessions()`, is sent under its own
record identifier: an anonymous person of one event, linked to nothing. A record a store recovers
after a relaunch keeps its session, so it goes out under the `distinct_id` of its first send.

PostHog records the address each request comes from as `$ip`, unless the project discards client IP
data, and its GeoIP transformation adds a location even when it does. The encoder sends
`$geoip_disable: true` on every event, so PostHog adds no location; choose whether to keep `$ip` in
the project's settings.

A `Sensitive` value is never sent, whatever the record reveals, so a value meant for PostHog isn't
`Sensitive`. Properties whose names PostHog reads as settings or identity (`$`-prefixed ones, which
only a hand-written `Encodable` conformance can write, and `distinct_id`) are left out and
logged. Like the collector's encoder, it leaves out a record the plan doesn't describe, one that
isn't `Encodable`, one holding a value JSON can't and one whose timestamp has no ISO 8601 form,
and also one whose event name starts with `$`, as PostHog keeps those names for its own events,
and one too large for PostHog's event limit.
It logs each at error level, and the destination reports each on `dropReports` as
`HTTPDropReport.skipped(_:)`.

### Amplitude

To send to an Amplitude project, make the destination with
`HTTPDestination.amplitude(apiKey:region:plan:)` (module ``/AmplitudeEncoding``). It posts to the
HTTP V2 API of the region where the project's data resides, `.us` for Amplitude's default data
center or `.eu` for its EU one. The region has no default, as events posted to the other region's
endpoint never reach the project. The destination sends no trace context in the header
fields, and splits each batch into requests of at most 10 events and 1 MB, which a project on any
Amplitude plan accepts. The API key goes in the body; like every Amplitude client's, it is public.
The factory throws `AmplitudeSetupError` for an empty key and for an Amplitude Experiment
deployment key (`client-…` or `server-…`), which isn't the project's API key. The destination
retries 429 and 5xx responses and drops a request Amplitude rejects, such as one answered with
400 or 413. A record sent again in the same run keeps its `insert_id` and `device_id`, and
Amplitude drops a repeat of both. A record a store recovers after a relaunch keeps its session,
so it goes out with the same `device_id` and `insert_id`, and Amplitude drops it if it stored it
before the app ended.

```swift
let plan = try TrackingPlan()
let amplitude = try HTTPDestination.amplitude(
    apiKey: apiKey,
    region: .us,  // or .eu, where the project's data resides
    plan: plan)
let tracker = Tracker(enrichers: [.sessions()])
let delivery = tracker.records.batch().deliver(to: amplitude)
```

Each event's `device_id` is the record's session (`Enricher.sessions()`), and its `session_id` the
session's start in Unix milliseconds, so Amplitude groups the session's events. No `user_id` is
sent, nor anything else that identifies anyone: not the vendor identifier, the trace context, your
own context keys or an `ip`. Amplitude counts a user per `device_id` and bills by monthly tracked
users, so each session counts as one tracked user, and so does each record sent without a session. The encoder fills in Amplitude's own fields
for the app version, device model, operating system and language when the standard context
enrichers set them. Event names are sent as they are.

Amplitude can reject an event that has neither a `device_id` nor a `user_id`, so every event gets a
`device_id`. A record with no session is sent under its own record identifier, with no
`session_id`: an anonymous device of one event, linked to nothing. Either identifier is a UUID, well
over the 5 characters Amplitude requires.

A `Sensitive` value is never sent, whatever the record reveals. The encoder leaves out the same
records as the collector's encoder, and also one named as one of Amplitude's own events
(`[Amplitude] Start Session` and the rest of the `[Amplitude]` names, `$identify`,
`$groupidentify`), one whose timestamp has no epoch-milliseconds form, and one too large for a
request. The destination reports each on `dropReports` as `HTTPDropReport.skipped(_:)`.

### Mixpanel

To send to a Mixpanel project, make the destination with
`HTTPDestination.mixpanel(projectToken:region:plan:)` (module ``/MixpanelEncoding``). It posts to
the `/track` endpoint of the project's data residency: `.us` for Mixpanel's default, `.eu` or
`.india`. The region has no default, as Mixpanel ingests nothing for a project from another
residency's endpoint. The destination sends no trace context in the header fields, and splits each
batch into requests of at most 2,000 events and 2 MB.

The project token goes in each event. It is public, like every Mixpanel client's, and it is all
the destination takes. Mixpanel's import API takes the project's secret or a service account's
credentials instead; those belong on a server and must never ship in an app, so no Traffluent API
accepts them. The factory throws `MixpanelSetupError` for an empty token, and for one with a
character other than a letter or digit, which no project token has. That check matters because
Mixpanel may answer 200 to a token it doesn't know and store nothing.

The destination retries 429 and 5xx responses and drops a request Mixpanel rejects, such as one
answered with 400, 401 or 413. Its retries wait `ExponentialBackoff.mixpanel`: Mixpanel's
recommended schedule, 2 s doubling to 60 s, with full jitter, which is Traffluent's choice rather
than Mixpanel's. The destination asks for Mixpanel's verbose answer (`verbose=1`), and a 200
whose `status` is 0, which Mixpanel answers when it finds no valid event in the request, is dropped and
reported as `HTTPDropReport.rejectedInBody(status:reason:recordIDs:)` with Mixpanel's error. A
status of 1 doesn't confirm the token or the region: a wrong region, or a token of no project, may
still be answered with 1 and nothing stored, so check the project's Live View after setting the
destination up. A record
sent again in the same run keeps its `$insert_id` and `distinct_id`, and Mixpanel counts a repeat
of an event's name, `time`, `distinct_id` and `$insert_id` once. A record a store recovers after a
relaunch keeps its session, so it goes out with the same `distinct_id` and `$insert_id`, and
Mixpanel counts it once if it stored it before the app ended.

```swift
let plan = try TrackingPlan()
let mixpanel = try HTTPDestination.mixpanel(
    projectToken: projectToken,
    region: .us,  // or .eu or .india, where the project's data resides
    plan: plan)
let tracker = Tracker(enrichers: [.sessions()])
let delivery = tracker.records.batch().deliver(to: mixpanel)
```

Each event's `distinct_id` is the record's session (`Enricher.sessions()`), also sent as
`$device_id`, which Mixpanel's ID merge reads as an anonymous device. No `$user_id` is sent, nor
anything else that identifies anyone: not the vendor identifier, the trace context or your own
context keys. Under Simplified ID Merge, Mixpanel shows a session's events under
`$device:<session>`, and a sessionless record's under its bare record identifier. Mixpanel counts
a user per `distinct_id`, so each session is one user in its reports,
and so is each record sent without a session; on a plan billed by monthly tracked users, each
counts as one. Every event's `ip` is `0`, as is the endpoint's query, so Mixpanel adds no location
from the request's address. The encoder fills in Mixpanel's default properties for the app
version and build, device model, Wi-Fi and operating system when the standard context enrichers
set them. Event names are sent as they are.

A record with no session, from a tracker without `.sessions()`, is sent under its own record
identifier, with no `$device_id`: an anonymous user of one event, linked to nothing. Without a `distinct_id`, Mixpanel would attribute it to no user, or to a hash of the
request's address.

A `Sensitive` value is never sent, whatever the record reveals. The encoder leaves out the same
records as the collector's encoder, and also one whose event name starts with `$`, as Mixpanel's
own events' names do (`$identify`, `$create_alias`). It also leaves out one with a property
Mixpanel reads for itself: a `$`-prefixed one, or `token`, `time`, `distinct_id`, `ip` or `bucket`.
Such a property would change how Mixpanel ingests the event, or be replaced by the encoder's own
value, so the record is reported rather than sent without it. Rename the property, raising the
event's version, to send it; the encoder logs a notice for each such property in the plan when
the destination is made. The encoder also leaves out a record past Mixpanel's limits, which
Mixpanel would drop while answering 200: one of 255 properties or more, counting the members the
encoder adds, one holding an array of 255 elements or more, and one whose property nests objects
more than 3 deep. Last, the encoder leaves out a record whose timestamp is before 1971
or has no epoch-milliseconds form, and one too large for Mixpanel. The destination reports each on
`dropReports` as `HTTPDropReport.skipped(_:)`.

Mixpanel's track API ingests only events from the last 5 days, and answers status 1 to a request
it ingests some of, so the destination doesn't send it an older record. The encoder leaves out a
record tracked more than 119 hours (5 days less an hour, for clocks that disagree) before its
batch is encoded, such as one a store kept through a long time offline, or more than an hour after,
which Mixpanel rejects too, and reports it as `HTTPDropReport.skipped(_:)`. Each request has a
deadline 119 hours after its oldest record was tracked; a request still being retried when it
passes isn't sent again, and is reported as `HTTPDropReport.deadlineExceeded(deadline:recordIDs:)`.

### Segment, RudderStack and Customer.io

Segment, RudderStack and Customer.io Data Pipelines take the same batch call of the Segment spec,
so one module, ``/SegmentSpecEncoding``, sends to all three, with a factory for each. Each posts to
the endpoint's `/v1/batch`, sends no trace context, and splits each batch into requests of at most
2,500 calls and 500 KB, each call under 32 KB, which all three accept.

To send to a Segment source, make the destination with
`HTTPDestination.segment(writeKey:region:plan:)`. The region is the workspace's, `.us` for
Segment's default or `.eu`, and has no default, as Segment rejects events sent to the other
region's endpoint, or answers without an error and stores nothing.

```swift
let plan = try TrackingPlan()
let segment = try HTTPDestination.segment(
    writeKey: writeKey,
    region: .us,  // or .eu, where the workspace is
    plan: plan)
let tracker = Tracker(enrichers: [.sessions()])
let delivery = tracker.records.batch().deliver(to: segment)
```

To send to a RudderStack source, make it with
`HTTPDestination.rudderStack(writeKey:dataPlane:plan:)`, passing the data plane URL from the top of
the workspace's Connections page, or a self-hosted data plane's. The factory appends `/v1/batch`
itself, and throws `RudderStackSetupError` for a URL that isn't plain `https`, a local data plane's
included, or that ends in `/v1` or `/v1/batch`.

```swift
let plan = try TrackingPlan()
let rudderStack = try HTTPDestination.rudderStack(
    writeKey: writeKey,
    dataPlane: dataPlane,  // https://<workspace>dataplane.rudderstack.com
    plan: plan)
let tracker = Tracker(enrichers: [.sessions()])
let delivery = tracker.records.batch().deliver(to: rudderStack)
```

To send to a Customer.io workspace through its Pipelines API, make it with
`HTTPDestination.customerIO(apiKey:region:plan:)`, passing the source's public key (`pk_…`) and
the workspace's region, `.us` or `.eu`.

```swift
let plan = try TrackingPlan()
let customerIO = try HTTPDestination.customerIO(
    apiKey: apiKey,  // the source's public key, pk_…
    region: .us,  // or .eu, where the workspace is
    plan: plan)
let tracker = Tracker(enrichers: [.sessions()])
let delivery = tracker.records.batch().deliver(to: customerIO)
```

The key goes in the `Authorization` header field, never in the body: as HTTP Basic
authentication's user name, with an empty password, for Segment and RudderStack, and as a bearer
token for Customer.io. Each is a public client key, the one the vendor's own app and web libraries
ship, which lets a client send data to the source and read nothing. Customer.io's private keys
(`sk_…`) reach every Customer.io API, deleting people included, and must never ship in an app, so
the factory throws `CustomerIOSetupError` for one, as it does for a public key of the other
region. Each factory throws for an empty key.

Each record becomes a track call. Its `anonymousId` is the record's session
(`Enricher.sessions()`), its `messageId` the record's identifier, which a record sent again keeps,
and its `timestamp` the record's in ISO 8601. No `userId`, `identify` call or traits are sent, nor
anything else that identifies anyone: not the vendor identifier, the trace context or your own
context keys. The encoder fills in the spec's `context` fields for the app (its bundle identifier
as `namespace`, version and build), the device (`model`, and `type` as Segment's Swift library
names the platform), the locale, the network and the operating system, when the standard context
enrichers set them, with no `device.id` or `advertisingId`. Event names are sent as they are.

Every call's `context.ip` is `0.0.0.0`, which Segment takes as the user's address in place of the
request's, so it records none. RudderStack reads `context.ip` first for geolocation, but fills in
a `request_ip` from the request unless the call has one, and passes it on to its destinations, so
RudderStack's calls also carry `request_ip` as `0.0.0.0`. Segment's and Customer.io's specs have no
`request_ip`, and Customer.io's strict mode may refuse a member it doesn't know, so their calls
don't carry one. Customer.io's references don't say whether `context.ip` takes the place of the
address it reads from an HTTP request, so it may still record the request's.

No `sentAt` is sent, so each endpoint takes the timestamp as it is, uncorrected for the device's
clock: a request sent again carries the same body, whose `sentAt` would be the first attempt's.
RudderStack fills in `sentAt`, `originalTimestamp` and `channel` from when it received the call.

Each endpoint counts a user per `anonymousId`, so each session is one user in its reports, and so
is each record sent without a session; on a plan billed by monthly tracked users, each counts as
one. A record with no session, from a tracker without `.sessions()`, is sent under its own record
identifier: an anonymous user of one call, linked to nothing, as the spec rejects a call with
neither a `userId` nor an `anonymousId`. A record a store recovers after a relaunch keeps its
session, so it goes out with the `anonymousId` and `messageId` of its first send. Segment
deduplicates calls by `messageId` and drops most duplicates within about 24 hours, not all, so a
recovered record it stored before the app ended is most likely not stored again. RudderStack's and
Customer.io's API references don't say whether they deduplicate, so such a record may be stored
twice there.

A `Sensitive` value is never sent, whatever the record reveals. The encoder leaves out the same
records as the collector's encoder, and also one named as one of Customer.io's semantic events,
which act on the person rather than record what they did: `User Deleted`, `User Suppressed`,
`User Unsuppressed`, `Device Created or Updated`, `Device Deleted`, `Object Deleted`,
`Relationship Deleted` and `Report Delivery Event`. It leaves those out for Segment and RudderStack
too, as either can forward track calls to a Customer.io destination; rename such an event to send
it. The encoder logs a notice for each such name in the plan when the destination is made.
It also leaves out a record whose timestamp has no four-digit ISO 8601 year (before year 1 or
after 9999), and one too large for a call. The destination reports each on `dropReports` as
`HTTPDropReport.skipped(_:)`.

The endpoints don't report every loss. Segment answers 200 for every request but one too large or
not JSON, so a wrong region, a write key of no source, or a batch of more calls than it takes may
be answered 200 with nothing stored: check the source's debugger after setting the destination up.
RudderStack answers a wrong write key with 401 and a disabled source with 404, and the destination
drops and reports both. Customer.io answers 200 for a request it drops, a wrong key included,
unless it is in strict mode, so the destination sends `X-Strict-Mode: 1`: it then answers a wrong
key with 401 and a call it won't take with 400, which the destination reports. In strict mode it
refuses a whole batch for one bad call, so the encoder leaves out each call Customer.io documents
refusing; a 400 for anything else drops the whole request.

### Google Analytics

An app's events reach a Google Analytics 4 web stream through TraffluentCollector, which forwards
the records it accepts over the Measurement Protocol. The app holds no Google secret: it sends to
the collector with a `CollectorBatchEncoder`, as in <doc:ChoosingDestinations#A-server>, and its
tracker's sessions enricher gives each record the session the collector sends as its `client_id`.
In the app, in Swift:

```swift
let plan = try TrackingPlan()
let collector = HTTPDestination(
    endpoint: collectorURL,  // https://collector.example.com/v1/batches
    headerFields: [.authorization: "Bearer \(apiKey)"],  // the collector's API key, not Google's
    encoder: CollectorBatchEncoder(plan: plan))
// The sessions enricher gives each record the session the collector sends as its client_id.
let tracker = Tracker(enrichers: [.sessions()])
let delivery = tracker.records.batch().deliver(to: collector)
```

The measurement ID, the API secret and the region are set in the collector's environment, not in
Swift and not in the app:

```sh
SERVER_GA4_MEASUREMENT_ID=G-ABC123                 # the web stream's measurement ID
SERVER_GA4_API_SECRET=replace-with-the-api-secret  # one of that stream's Measurement Protocol API secrets
SERVER_GA4_REGION=global                           # or eu; global when unset
SERVER_TRACKING_PLAN=/srv/tracking-plan            # the exported plan, required to forward
```

The measurement ID and the API secret are set together; with neither set, nothing is forwarded.
The collector refuses to start when only some are set, when the region is neither
`global` nor `eu`, or when it has no tracking plan, which marks the properties it must never send.
Its `GET /v1/admin/forwarding` route and Forwarding screens report the stream, the region, the
pending, forwarded and skipped counts and the last failure, and never the API secret.

The collector writes the same requests as this section's encoder below: the session as
`client_id`, a version 7 session's start as `session_id`, `timestamp_micros`, ad consent denied,
and the properties as `params`, flattened with `_`, with nulls and every property the plan marks
sensitive left out. It sends no `user_id`, user properties, location, device or other context
value. It skips the records the encoder below leaves out for Google Analytics' naming and size
rules, and a record more than 72 hours older or 15 minutes newer than the moment it is encoded;
the collector logs and counts each, and the app's `dropReports` don't hear of them. It queues only
the records the plan accepted and it stored for the first time, so rejected records and the records
of a batch the app sends again are never forwarded, and neither are records stored before forwarding was
configured. It forwards from that durable queue, and sends a record again when a post fails or the
collector stops before settling it, so one Google stored before the answer was lost is counted
twice. The Measurement Protocol answers 2xx even for a wrong measurement ID or API secret: check
the property's Realtime report after setting the variables.

To send from a server of your own instead, such as a relay in front of Google Analytics, make the
destination there with `HTTPDestination.googleAnalytics(measurementID:apiSecret:region:plan:)`
(module ``/GoogleAnalyticsEncoding``); the rest of this section describes it. It posts to the
Measurement Protocol's `/mp/collect` endpoint: `.global` for Google's default, or `.eu` to have
Google collect the data in the EU. The destination sends no trace context in the header fields,
and splits each batch into requests of one client's events, at most 25 events and 100 KB each.

The Measurement Protocol takes only requests carrying one of the stream's API secrets, and anyone
who holds that secret can send events to the property, spam included. An app's binary can be read,
so a secret shipped in one is public. The module is therefore compiled for macOS and Linux alone:
an app for iOS, iPadOS, tvOS, watchOS, visionOS or Mac Catalyst that calls the factory fails to
compile. A Mac app compiles the factory, but the factory refuses it at run time, throwing
`GoogleAnalyticsSetupError.appBundle` when the main bundle is an `.app` or an `.appex`. The factory
also throws for an empty measurement ID, for one that isn't `G-` followed by uppercase letters and
digits, and for an empty API secret. The secret is in every request's URL, so don't log the
destination, its requests or a transport's URLs.

A relay reads each body the app sent back into records with a `CollectorBatchDecoder` (module
``/CollectorEncoding``), which keeps each record's identifier, timestamp and event and the app's
`SessionKey`, and hands the records to the destination's `receive(_:)`. The GoogleAnalyticsEncoding
module's article shows one. It doesn't track them again through a tracker with `.sessions()`, which
would send every user of the app as one `client_id`. A server that tracks its own events does use a
tracker:

```swift
let plan = try TrackingPlan()
let googleAnalytics = try HTTPDestination.googleAnalytics(
    measurementID: measurementID,  // the web or data stream's, G-…
    apiSecret: apiSecret,  // from the server's configuration, never an app's
    region: .global,  // or .eu, to have Google collect the data in the EU
    plan: plan)
// A server tracking its own events: its sessions are the server's.
let tracker = Tracker(enrichers: [.sessions()])
let delivery = tracker.records.batch().deliver(to: googleAnalytics)
```

Each request's `client_id` is the record's session (`Enricher.sessions()`), written as the two
halves of its UUID in decimal joined by a period, the form the Measurement Protocol asks for, and
each event's `session_id` parameter is the session's start in Unix milliseconds. No `user_id`,
user properties, location, IP address, device or user agent is sent, nor the vendor identifier,
the trace context, the standard context or your own context keys. Every request sends ad consent
as denied. Google Analytics counts a user per `client_id`, so each session is one user in its
reports, and so is each record sent without a session, which goes out under its own record
identifier. Without `engagement_time_msec`, which Traffluent doesn't measure, the events don't
count toward engagement time or engaged sessions, and the Realtime and Users reports can show no
users while events arrive: check the event counts instead.

The Measurement Protocol has no field that identifies an event, so Google Analytics counts every
event it receives. A record sent again, by a retry after Google stored it, by a delivery that
sends a cancelled batch again, or by a store's redelivery after a relaunch, is counted twice.

A `Sensitive` value is never sent, whatever the record reveals. Google Analytics takes only
strings, numbers and booleans as parameters, so a nested value is spread into a parameter for each
value it holds, named after its path joined by `_`. The encoder leaves out the same records as the
collector's encoder, and also one that breaks a Measurement Protocol rule: an event or parameter
name longer than 40 bytes, not starting with a letter, or holding anything but letters, numbers
and `_`; a name Google Analytics keeps for itself, or takes only from an app stream
(`session_start`, `error`, `screen_view`, a `firebase_`, `ga_` or `google_` parameter); more than
25 parameters; a string longer than 100 bytes, though a Google Analytics 360 property takes 500
characters; and a record tracked more than 71 hours before its batch is encoded, an hour short of
the 72 Google Analytics takes, or more than 15 minutes after. Google Analytics answers 2xx to such an event and, under its default relaxed
validation, stores it without the offending parameter or under a name it never checked, so the
encoder reports the record rather than send it. The destination reports each on `dropReports` as
`HTTPDropReport.skipped(_:)`, and the encoder logs a notice for each such name in the plan when the
destination is made.

The Measurement Protocol doesn't report any loss. It answers 2xx to every request it receives,
including one it can't read and one with a wrong measurement ID or API secret, and stores nothing
for them, so check the property's Realtime event counts after setting the destination up. Its
validation server, `/debug/mp/collect`, checks a body's shape but not the measurement ID or the
API secret. A request is encoded once and retried as it is, so each request's deadline is 71 hours
after its oldest record was tracked: one still failing by then isn't sent again, which would have
Google Analytics store its oldest records as 72 hours old. The whole request is dropped, its younger
records too, and reported as `HTTPDropReport.deadlineExceeded(deadline:recordIDs:)`.

### Snowplow

To send to a Snowplow pipeline, make the destination with
`HTTPDestination.snowplow(collector:vendor:appID:plan:)` (module ``/SnowplowEncoding``). It posts
to the collector's `/com.snowplowanalytics.snowplow/tp2` endpoint, after the URL's path, sends no
trace context in the header fields, and splits each batch into requests of at most 25 events and
40,000 bytes, the limits of Snowplow's own mobile trackers, sending a larger event, of up to
150,000 bytes, in a request of its own, as they do. A collector takes events from anyone,
so there is no secret and the destination builds on every platform. The factory throws for a
collector URL that isn't `https`, has no host, a user name, a query or a fragment, or already ends
in the endpoint; for a vendor Iglu doesn't take; and for an empty app ID or one longer than 255
UTF-16 code units.

```swift
let plan = try TrackingPlan()
let snowplow = try HTTPDestination.snowplow(
    collector: collector,  // https://collector.example.com
    vendor: "com.example",  // the Iglu vendor the plan is exported under
    appID: "shop-ios",
    plan: plan)
let tracker = Tracker(enrichers: [.sessions()])
let delivery = tracker.records.batch().deliver(to: snowplow)
```

Each record is a self-describing event: Snowplow validates its data against the schema its URI
names, `iglu:<vendor>/<name>/jsonschema/<version>-0-0`, before loading it. Those schemas are your
plan's, exported as an Iglu registry (<doc:TrackingPlanWorkflow#Exporting-an-Iglu-registry>) and
published before the release that sends them. Version N of an event is SchemaVer `N-0-0`. For
Iglu Server, a compatible change at the same version is written as `N-0-1` and on, each
superseding the ones before; a static repository doesn't supersede, so for one the export refuses
the change, as it refuses a breaking change for either: raise the event's version. An event whose name holds anything but ASCII letters, digits, `-` and `_` has no Iglu
schema, so its records are left out, and the encoder logs a notice for each such event in the plan
when the destination is made.

The record's session (`Enricher.sessions()`) is its `sid`, and nothing else identifies it. No
`duid`, `uid`, `nuid` or `tnuid` is sent, no `client_session` entity, whose `userId` lasts across
sessions, and no IDFV, IDFA, vendor identifier or trace context. Left alone, the collector would
set an `sp` cookie, which `URLSession` keeps and sends back, and record the request's IP address,
so every request carries `SP-Anonymous: *`: the collector then sets and reads no cookie, records
`network_userid` as all zeros, and records no address. A record with no session is sent without a
`sid`. Snowplow's unified data model reads a mobile session from the `client_session` entity, so
set its `snowplow__session_identifiers` to `[{"schema": "atomic", "field": "domain_sessionid"}]`
for these events. Each event's `dtm` and `ttm` are the record's timestamp, so Snowplow's `derived_tstamp` is
when the event was tracked; no `stm` is sent, as a retried request would carry the first attempt's
and shift the event by the time spent retrying. The standard context goes in Snowplow's
`mobile_context` and `application` entities, and the platform `p` is `mob`, `tv`, `pc`, or `app`
when the record has no device. A `Sensitive` value is never sent, whatever the record reveals.

The encoder leaves out the same records as the collector's encoder, and also one whose event Iglu
can't name, whose version is below 1, whose timestamp is outside the years 0 to 9999, which
Snowplow's enrichment fails, or whose JSON is over 150,000 bytes (`oversized`), within the
smallest of a pipeline's streams, SQS's 192 kB. The destination reports each on `dropReports` as
`HTTPDropReport.skipped(_:)`.

The collector doesn't report what Snowplow later rejects. It answers 200 to every request it can
read, and an event that fails validation, names a schema the pipeline's Iglu resolver can't find,
or is larger than the pipeline's stream takes becomes a failed event, kept out of the warehouse,
though the destination counted it as delivered. Watch the pipeline's failed events after a change
to the plan. Snowplow doesn't remove duplicates as they arrive: a record sent again keeps its
`eid`, so Snowplow's data models, which deduplicate on `event_id`, count it once.

### TelemetryDeck

To send to TelemetryDeck, make the destination with
`HTTPDestination.telemetryDeck(appID:namespace:testMode:plan:)` (module ``/TelemetryDeckEncoding``).
It posts to Ingest API v3 at `https://nom.telemetrydeck.com/v3/<namespace>/`, sends no trace
context in the header fields, and splits each batch into requests of at most 100 signals, as
TelemetryDeck's SwiftSDK sends them, and 1,000,000 bytes, the encoder's own bound, as TelemetryDeck
documents no limit on a request. The app ID is in every app TelemetryDeck's own
SDKs ship, so it is no secret, and the destination builds on every platform. The factory throws
for an app ID that is empty or only whitespace, and for a namespace that holds anything but ASCII
letters, digits, `.`, `_` and `-`, or is `w`, `.` or `..`. `testMode` has no default: pass `true`
for builds whose signals only TelemetryDeck's Test Mode should show, such as debug builds.

```swift
let plan = try TrackingPlan()
let telemetryDeck = try HTTPDestination.telemetryDeck(
    appID: appID,  // from the app's settings in the TelemetryDeck dashboard
    namespace: "com.example",  // your organization's namespace
    testMode: false,  // true for builds whose signals only Test Mode should show
    plan: plan)
let tracker = Tracker(enrichers: [.sessions()])
let delivery = tracker.records.batch().deliver(to: telemetryDeck)
```

The record's session (`Enricher.sessions()`) is its `sessionID`, and, hashed as TelemetryDeck's
SDKs hash a user identifier (SHA-256 of the lowercase UUID, in lowercase hex, with the SDKs'
default, empty salt), its `clientUser`. TelemetryDeck salts and hashes it again on its server, and
the `sessionID` holds the same session in the clear, so the destination takes no salt of its own. Nothing else identifies it: no vendor identifier, device identifier,
account or trace context. TelemetryDeck counts users by `clientUser`, so its user counts are
session counts, and its retention shows how long a session lasts. To count devices, put
`VendorIdentifierKey` in the records' context and send them through a destination that reads it,
or write your own enricher and encoder. A record with no session, from a tracker without
`.sessions()`, is its own user: its `clientUser` is the hash of its identifier, and it has no
`sessionID`. A record a store recovered keeps its session.

Each signal's `type` is the event's name and its `receivedAt` the record's timestamp. Its
properties sit beside them, each keeping its JSON type. An object or array is flattened into
dotted names (`cart.size`, `tags.0`), as TelemetryDeck doesn't index nested values. The standard
context becomes TelemetryDeck's built-in parameters: `TelemetryDeck.AppInfo.version` and
`.buildNumber`, `TelemetryDeck.Device.modelName`, `.operatingSystem`, `.platform` and the system
versions, `TelemetryDeck.RunContext.locale` and `.language`, and
`TelemetryDeck.UserPreference.region`. A `Sensitive` value is never sent, whatever the record
reveals.

The encoder leaves out the same records as the collector's encoder, and also one whose event name
or parameter name holds anything but ASCII letters, digits, `.`, `_` and `-`, for which
TelemetryDeck would refuse the whole request, or that starts with `TelemetryDeck.`, in any case,
the scope TelemetryDeck reserves for its SDKs and its server; one with a parameter named exactly as
a signal's own member (`appID`, `clientUser`, `receivedAt`, `type`, `sessionID`, `isTestMode` or
`floatValue`), which it would replace in the flat signal; one whose values flatten to one name
twice; one whose timestamp is outside the years 1 to 9999; and one whose JSON is over 333,333 bytes
(`oversized`), a third of TelemetryDeck's limit of 1,000,000 bytes a signal, leaving room for the
escapes a re-encoder commonly adds. The destination reports each on `dropReports` as `HTTPDropReport.skipped(_:)`.

TelemetryDeck answers 200 to any namespace and app ID, so a typo in either loses every signal
without an error: check that the first ones reach the dashboard. It doesn't remove duplicates, so
a record sent again, after a retry whose answer was lost or a store's redelivery, is counted twice.

### Matomo

To send to a Matomo installation, make the destination with
`HTTPDestination.matomo(url:siteID:dimensions:category:plan:)` (module ``/MatomoEncoding``). It
posts bulk tracking requests to `matomo.php` under the URL Matomo is installed at, sends no trace
context in the header fields, and splits each batch into requests of at most 20 records, as
Matomo's iOS SDK sends them, and 1,000,000 bytes, under nginx's default limit on a body, as Matomo
documents none. Matomo needs no key to track, so the destination builds on every platform. The
factory throws for a URL that isn't `https`, has no host, holds a user name, query or fragment, or
already ends in a `.php` file such as `matomo.php`; for a site ID below 1; for a category that is
empty or longer than Matomo stores; and for dimensions that break a rule.

```swift
let plan = try TrackingPlan()
let matomo = try HTTPDestination.matomo(
    url: url,  // where Matomo is installed: https://analytics.example.com
    siteID: 3,  // the app's site in Matomo
    dimensions: ["plan": 1],  // custom dimensions made in Matomo
    category: "Shop",  // each event's category
    plan: plan)
let tracker = Tracker(enrichers: [.sessions()])
let delivery = tracker.records.batch().deliver(to: matomo)
```

Each record is a Matomo event. Its category, `e_c`, is the one you pass, such as your app's name,
and its action, `e_a`, is the event's name, so Matomo's Event Actions report lists your events; no
event name or value is sent. Matomo numbers each site's custom dimensions as you make them, so
`dimensions` maps your plan's property names to their IDs. A mapped property's value is sent as
`dimension<ID>`, a string as it is and anything else as its JSON. A `Sensitive` property is never
sent, so the factory throws for one that is mapped. A property with no dimension is
left out of every request, and the destination logs a notice for each event that has one, once,
when it is made. `MatomoDimensions.unmappedProperties(in:)` lists them for a test. Make the
dimensions with the Action scope, so each event keeps its own value.

The record's session (`Enricher.sessions()`) is its visitor: `_id` is the session's last 64 bits,
in 16 hexadecimal digits, and nothing else identifies it, no `uid`, `cid` or device identifier. So
Matomo's visitors are sessions. A record with no session, from a tracker without `.sessions()`, is
its own visitor, by its identifier's last 64 bits; a record a store recovered keeps its session. A session is one visit while the sessions enricher's
timeout is no longer than Matomo's visit length, 30 minutes by default. Matomo may still fold a session's first event into
another visit from the same IP address and User-Agent within 30 minutes, an earlier session's or
someone else's on the same network, unless `trust_visitors_cookies = 1` is set in its
`config.ini.php`. Matomo records the IP address of each request; whether it masks it and what it
uses it for are its privacy settings, which no app can override without a token.

The destination never sends a `token_auth`: a token is a secret, and an app holds none. Without
one, Matomo takes an event's time only when it is less than a day old, and answers 200 while
storing nothing for an older one. So the encoder leaves out a record tracked more than 23 hours
before or after the batch is encoded, the hour to spare for a queue on the server and clocks that disagree, and reports it as
`timestampOutsideWindow`: a record a store kept offline for longer, or that waited that long in
the buffer. A request is encoded once and retried as it is, so each request's deadline is 23 hours
after its oldest record was tracked: one still failing by then isn't sent again, which Matomo
would answer with 200 while storing nothing. The whole request is dropped, its younger records
too, and reported as `HTTPDropReport.deadlineExceeded(deadline:recordIDs:)`. A clock that reads NaN or infinite has
every record reported. To keep older records, send them to a server of
yours that forwards to Matomo with a token.

The encoder leaves out the same records as the collector's encoder, and also one whose event name
is empty once trimmed or longer than the 4,096 characters Matomo stores; one whose time is outside
the 23 hours; one with a dimension's value over the 250 characters Matomo keeps, counted as Matomo
stores it, with `&` and the other characters HTML escapes as their entities; and one too large for
a request (`oversized`). The destination reports each on `dropReports` as
`HTTPDropReport.skipped(_:)`.

Matomo answers 200 to any bulk request it can read, with how many tracking requests it tracked
and how many it refused as invalid. When it refused every one, as for a site ID of no site, the
destination drops the request and reports it as `HTTPDropReport.rejectedInBody`. When it tracked
some and refused others, its answer doesn't say which without a token, so the request counts as
delivered and the destination logs a notice. When the counts fall short of the request, Matomo
skipped some, as after a database lock wait timeout, and the destination sends the request again
until its 23-hour deadline. Check that the first events reach the site's Visits
Log. It doesn't remove duplicates, so
a record sent again, after a retry whose answer was lost or a store's redelivery, is counted twice.

### Heap

To send to Heap, make the destination with `HTTPDestination.heap(appID:region:plan:)` (module
``/HeapEncoding``). It posts to Heap's server-side bulk track API at
`https://heapanalytics.com/api/track`, or `https://c.eu.heap-api.com/api/track` for a project in
Heap's EU data center, sends no trace context in the header fields, and splits each batch into
requests of at most 1,000 events, the most the API takes, and 1,000,000 bytes, the encoder's own
bound, as Heap documents none. The API takes the environment's app ID and no API key, and Heap's
own SDKs ship the app ID in every app, so the destination builds on every platform. The factory
throws for an app ID that is empty, only whitespace, or anything but ASCII digits. `region` has no
default.

Heap's server-side API complements its SDKs, and Heap says "you can only send events to
identified users". Every user this destination makes has only server-side events, so Heap shows
the user's events as hidden (its Hidden Events category), leaves them out of its Sessions list, as
it doesn't sessionize them, and matches none of them with a session filter on a user property.
Seeing events in Heap's Live data feed isn't enough: confirm that they appear in the charts you
mean to use.

```swift
let plan = try TrackingPlan()
let heap = try HTTPDestination.heap(
    appID: appID,  // the environment's ID, from Heap's project settings
    region: .us,  // or .eu, where the project's data resides
    plan: plan)
let tracker = Tracker(enrichers: [.sessions()])
let delivery = tracker.records.batch().deliver(to: heap)
```

The record's session (`Enricher.sessions()`) is its `identity`, as a lowercase UUID. Nothing
else identifies it: no `user_id`, `session_id`, vendor identifier, device identifier, account or
trace context. Heap makes a user of each identity it hasn't seen and keeps it, so its users are
sessions, and its user counts and retention describe sessions, not people. A record with no
session, from a tracker without `.sessions()`, is its own user, by its identifier; a record a
store recovered keeps its session.

Each event's `event` is the event's name, its `timestamp` the record's, and its
`idempotency_key` the record's identifier, so Heap stores a record sent twice under the same
identity once, a record a store recovered after a relaunch included. Its properties
are flattened into dotted names (`cart.size`, `tags.0`), as Heap takes only numbers and strings: a
boolean is the string `true` or `false`, and `nil` is left out. The standard context isn't sent,
as Heap keeps no built-in property of a server-side event, and app and device fields among the
event's own properties could collide with your names. A `Sensitive` value is never sent,
whatever the record reveals.

The encoder leaves out the same records as the collector's encoder, and also one whose event name
is over the 1,024 characters Heap takes; one with a property named `user_id`, `session_id` or
`screen_name`, which Heap reserves; one with a property name or string value of 1,024 characters
or more, counted in UTF-16, as Heap takes fewer; one whose values flatten to one name twice; one
whose timestamp is outside the years 1 to 9999; and one too large for a request (`oversized`). The
destination reports each on `dropReports` as `HTTPDropReport.skipped(_:)`.

Heap answers 400 to a request it can't take, which the destination drops and reports whole. Its
docs don't say what it answers to an app ID of no environment, so confirm that the first events
appear in your charts.

Heap takes 15,000 events a minute from one environment, shared by every device sending to it:
about 21.6 million events a day at a steady rate, and less in a burst. It takes 1,000 events a
minute from one identity, which here is one session, so a session whose own backlog holds more than
1,000 events goes past it. Heap's docs don't say what it answers past either limit. A 429 is
retried on the destination's jittered backoff, which doesn't read `Retry-After`, so a backlog can grow; a 400
drops the whole request, reported as rejected. Requests keep Heap's bulk maximum of 1,000 events,
as a smaller batch doesn't pace requests and so wouldn't avoid the limit.

### Aptabase

To send to Aptabase, make the destination with
`HTTPDestination.aptabase(appKey:host:isDebug:plan:)` (module ``/AptabaseEncoding``). The app
key says where it posts: an `A-EU-` key to `https://eu.aptabase.com/api/v0/events`, an `A-US-` key
to `https://us.aptabase.com/api/v0/events`, and a self-hosted `A-SH-` key to `/api/v0/events`
under the `host` you pass, which must be `https`. It sends the key in the `App-Key` header field
and no trace context, and splits each batch into requests of at most 25 events, the most Aptabase
takes, and 1,000,000 bytes, the encoder's own bound. Aptabase's own SDKs ship the app key in every
app, so it is no secret, and the destination builds on every platform. The factory throws for a
key that is empty or only whitespace, isn't `A-`, a region, `-` and ASCII letters and digits, or
has a region other than `EU`, `US`, `SH` and `DEV`; for a self-hosted key without a host, or a
cloud key with one; and for a host that isn't a plain `https` URL. `isDebug` has no default: pass
`true` for builds whose events only Aptabase's Debug mode should show, such as debug builds.

```swift
let plan = try TrackingPlan()
let aptabase = try HTTPDestination.aptabase(
    appKey: appKey,  // from the app's Instructions page: A-EU-…, A-US-… or A-SH-…
    isDebug: false,  // true for builds whose events only Debug mode should show
    plan: plan)
let tracker = Tracker(enrichers: [.sessions(), .application(), .device(), .operatingSystem(), .locale()])
let delivery = tracker.records.batch().deliver(to: aptabase)
```

Aptabase counts users itself: its server hashes each request's IP address and `User-Agent` with a
salt it changes every day, so a user is one address and client on one day, and no identifier the
app sends changes that. It also looks up each request's IP address and stores its country and
region with every event in the request. The record's session (`Enricher.sessions()`) is its `sessionId`, as a
lowercase UUID, and nothing else identifies it: no vendor identifier, device identifier, account
or trace context. A record with no session, from a tracker without `.sessions()`, is a session of
its own, by its identifier; a record a store recovered keeps its session.

Each event's `eventName` is the event's name and its `timestamp` the record's. Its `props` are its
properties, flattened into dotted names (`cart.size`, `tags.0`), as Aptabase keeps only a
placeholder for an object or array: a boolean stays a boolean, which Aptabase stores as `true` or
`false`, and `nil` is left out. Its `systemProps` are the standard context: `osName`, `osVersion`,
`appVersion`, `appBuildNumber`, `deviceModel` and `locale`, which Aptabase's dashboard breaks its
counts down by, so give the tracker the standard context enrichers, or those breakdowns are empty.
A value longer than Aptabase takes, such as a build number over 20 characters, is left out and
the event sent without it, as Aptabase would refuse the whole request. They also hold `isDebug`, as you pass it, as Aptabase shows debug events only in its Debug mode
and keeps them for months rather than years, and `sdkVersion`, `Traffluent`, which Aptabase
requires and keeps but its events dashboard doesn't show. A `Sensitive` value is never sent,
whatever the record reveals.

The encoder leaves out the same records as the collector's encoder, and also one whose event name
is only whitespace or over the 60 characters Aptabase takes, for which it would refuse the whole
request; one with a property name that is empty, only whitespace or over 40 characters, or a
string value over 180, counted in UTF-16, which Aptabase would drop or cut short; one with a
number of magnitude 2⁹⁶ or more, past the .NET `decimal` Aptabase stores; one whose values
flatten to one name twice; one whose timestamp is outside the years 1 to 9999; one tracked more than 23 hours before its
batch is encoded, as Aptabase drops an event more than a day old while answering 200; and one too
large for a request (`oversized`). The destination reports each on `dropReports` as
`HTTPDropReport.skipped(_:)`, and a request still failing 23 hours after its oldest record as
`HTTPDropReport.deadlineExceeded(deadline:recordIDs:)`.

Aptabase answers 200 to a key of no app, and to one of an account it has locked, such as one past
its plan's monthly events, and stores nothing. Its body then holds an error, so the destination
drops the request and reports it as `HTTPDropReport.rejectedInBody` with Aptabase's error. Check
that the first events reach the app's Live View all the same. It doesn't remove duplicates, so a record sent again, after a retry whose answer was
lost or a store's redelivery, is counted twice. It takes 20 requests a second from one IP
address and answers 429 past it, which the destination retries on its backoff. It answers 418
when a request's body arrives slower than 60 bytes a second after a 10-second grace period, as
over a poor connection, and the destination retries that on its backoff too, until the request's
deadline.

### Memory

To read what was tracked inside the app, deliver to an `InMemoryDestination` as well (module
``/Destinations``): for an event inspector in a debug build, a recent-activity view, a SwiftUI
preview, or a test of what your code tracks. It keeps the newest 1,000 records, or as many as you
pass as `capacity:`, dropping the oldest across batches; `InMemoryDestination.unbounded()` keeps
every one. Read it with `events(of: SignedUp.self)`, `records` or `batches`, or wait on
`deliveries`, which announces each batch to one reader at a time: a second waits its turn until the
first one's iteration ends or its iterator is released. A reader that stops calling `next()` but
keeps its iterator keeps the turn.

### Sensitive values and call sites

A property that destinations shouldn't see unless they must is a `Sensitive` value. A destination
reads it only through the record, with `reveal(_:)`, and printing or mirroring it shows
`<redacted>`. `redactingSensitiveValues()` makes a destination's records reveal nothing, and
`droppingCallSite()` removes their call sites. Every other destination receives both:

```swift
@Event
struct SignedIn {
    var email: Sensitive<String>
}

let backend = InMemoryDestination()
let vendor = InMemoryDestination()
let tracker = Tracker()
let delivery = tracker.records.batch().deliver(
    to: backend,
    vendor.redactingSensitiveValues().droppingCallSite()
)
tracker.track(SignedIn(email: Sensitive("ada@example.com")))
await tracker.finish()
try await delivery.execute()
let event = backend.events(of: SignedIn.self)[0]
let email = backend.records[0].reveal(event.email)    // "ada@example.com"
let redacted = vendor.records[0].reveal(event.email)  // nil
let callSite = vendor.records[0].sourceLocation       // nil
```

`accepting(_:)` narrows a destination to the consent categories it serves (<doc:ConsentGating>).

### Context for one destination

An enricher given to the tracker runs on its worker, so every destination sees what it sets. To
add a value that only one destination should receive, such as a deployment region your own backend
reads, apply `enriched(by:)` to that destination:

```swift
import Instrumentation

enum RegionKey: ServiceContextKey {
    typealias Value = String
}

let backend = InMemoryDestination()
let vendor = InMemoryDestination()
let tracker = Tracker()
let delivery = tracker.records.batch().deliver(
    to: backend.enriched(by: Enricher { $0[RegionKey.self] = "eu-west" }),
    vendor
)
tracker.track(SignedUp(plan: "pro"))
await tracker.finish()
try await delivery.execute()
let region = backend.records[0].context[RegionKey.self]       // "eu-west"
let vendorRegion = vendor.records[0].context[RegionKey.self]  // nil
```

The enricher runs as the delivery hands each batch to that destination, so it reaches every record
the destination receives, however the event was tracked: through any copy of the tracker, from a
detached task handed the tracker, or recovered by a store after a relaunch. That makes it the place
for values about the destination or the delivery, such as a region or a deployment tag, and not for
values about the event. A record recovered after a relaunch would get this run's app version, and
the network connection at upload rather than when it was tracked, so keep the standard context
enrichers and `.sessions()` on the tracker. Records an enricher adds before a record, as the
sessions enricher adds `SessionStarted`, are left out at a destination, since they would skip the
tracker's consent, samplers and store, and `enriched(by:)` logs a warning when given one.

Combined with the other modifiers, the one applied last sees each record first. Under
`redactingSensitiveValues()` a `Sensitive` value the enricher sets stays hidden in either order,
and inside `accepting(_:)` the enricher runs only on the records accepted. For which enricher has
the last word on a key, see "Context and enrichers" in <doc:TrackingEvents>.
