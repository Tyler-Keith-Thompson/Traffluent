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
`Encodable`, or when a value has no JSON form, such as a NaN. The destination logs each skipped
record at error level and reports it on `dropReports` as `HTTPDropReport.skipped(_:)`. A batch with
no record the encoder can write sends nothing.

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
isn't `Encodable` and one holding a value JSON can't, and also one whose event name starts with
`$`, as PostHog keeps those names for its own events, and one too large for PostHog's event limit.
It logs each at error level, and the destination reports each on `dropReports` as
`HTTPDropReport.skipped(_:)`.

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
