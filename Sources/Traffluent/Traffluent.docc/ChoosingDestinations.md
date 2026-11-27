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
answered with 2xx. The waits start at 1 second and double up to 60 seconds; pass an
`ExponentialBackoff` as `backoff:` for others, and a test clock as `clock:` in tests. The
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
gets one. A record with no session, from a tracker without `.sessions()` or recovered by a store
after a relaunch (recovered records keep no context), is sent under its own record identifier: an
anonymous person of one event, linked to nothing.

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
Amplitude drops a repeat of both. A record a store recovers after a relaunch has no session, so it
goes out under its own identifier as `device_id`; if Amplitude stored it before the app ended, it
is stored twice.

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
Mixpanel answers 200 to a token it doesn't know and stores nothing.

The destination retries 429 and 5xx responses and drops a request Mixpanel rejects, such as one
answered with 400, 401 or 413. A wrong region, or a token of no project, may be answered with 200
and nothing stored, so check the project's Live View after setting the destination up. A record
sent again in the same run keeps its `$insert_id` and `distinct_id`, and Mixpanel counts a repeat
of an event's name, `time`, `distinct_id` and `$insert_id` once. A record a store recovers after a
relaunch has no session, so it goes out under its own identifier as `distinct_id`; if Mixpanel
stored it before the app ended, it is stored twice.

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

A record with no session, from a tracker without `.sessions()` or recovered by a store, is sent
under its own record identifier, with no `$device_id`: an anonymous user of one event, linked to
nothing. Without a `distinct_id`, Mixpanel would attribute it to no user, or to a hash of the
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

Mixpanel doesn't report every loss. It answers 200 even when it ingests none of a request's
events, and its track API ingests only events from the last 5 days, so a record older than that
when it is sent, such as one a store kept through a long time offline, counts as delivered and
isn't stored.

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
one. A record with no session, from a tracker without `.sessions()` or recovered by a store after a
relaunch, is sent under its own record identifier: an anonymous user of one call, linked to
nothing, as the spec rejects a call with neither a `userId` nor an `anonymousId`. Segment
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
