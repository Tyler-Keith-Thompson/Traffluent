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
drop, pass the delivery a `bufferDropReporter`:

```swift
let (bufferDrops, bufferDropReporter) = AsyncStream.makeStream(of: BufferDropReport.self)
let delivery = tracker.records.batch().deliver(to: collector, bufferDropReporter: bufferDropReporter)
let watching = Task {
    for await drop in bufferDrops where drop.storedRecordCount < drop.recordCount {
        print("Lost \(drop.recordCount - drop.storedRecordCount) events tracked from \(drop.timestamps.lowerBound)")
    }
}
```

A report names the destination by its place in `deliver(to:)`'s list, counting from 0. It also
gives how many records the batch held, when they were tracked, and how many of them a store keeps
to send again. The delivery logs each drop too, and never finishes the reporter, so one reporter
can serve every delivery that replaces the last.

Some batches won't succeed if sent again, so they are dropped: one the endpoint answers with any
other status, one whose request the transport can never send (a malformed URL, a scheme it doesn't
support, or an `http` URL that App Transport Security refuses), and one the encoder can't encode.
The destination logs each at error level and reports it on `dropReports`, with the records'
identifiers and the status, the transport's reason or the encoder's error. Cancelling the delivery
stops the retries.

The bootstrapped tracing instrument, or the one you pass as `instrument:`, injects the trace
context of the batch's first record into the request's header fields, so a server that extracts it
joins the request to the app's trace. The encoder's `Content-Type` always wins, and with no
instrument bootstrapped no header is added. Only the first record's context travels in the header
fields; write each record's context into the body if the server needs it.

To send to a self-hosted TraffluentCollector, give `HTTPDestination` a
`CollectorBatchEncoder(plan:)` (module ``/CollectorEncoding``) as its encoder, and the collector's
API key as an `Authorization: Bearer` header field. It writes the collector's ingest format: each
record's identifier (which a redelivered record keeps), its name, timestamp and redelivery marker,
its properties read through the event's schema in your `TrackingPlan`, and its standard context and
trace context. A `Sensitive` value is sent only while the record reveals it.

A record the encoder can't write is left out of the request, and the rest of its batch is sent.
That happens when the plan has no schema for the record's event at its version (an event the
library tracks, such as `SessionStarted`, that the plan doesn't list), when the event isn't
`BinaryCodable`, or when a value has no JSON form, such as a NaN. The encoder logs each skipped
record at error level, and `batch(of:)` returns them as `SkippedRecord`s. A batch with no record
the encoder can write sends nothing.

### PostHog

To send to PostHog, Cloud or self-hosted, give `HTTPDestination` a
`PostHogBatchEncoder(projectToken:plan:)` (module ``/PostHogEncoding``, which `import Traffluent`
leaves out) and your instance's `/batch/` URL. The project token goes in the body; it is public,
like every PostHog client's, so no header is needed. The destination retries and reports drops as
it does for any server, and a record sent again keeps its `uuid`.

```swift
let plan = TrackingPlan(schemas: [SignedUp.schema, SessionStarted.schema, SessionEnded.schema])
let postHog = HTTPDestination(
    endpoint: postHogBatchURL,  // https://us.i.posthog.com/batch/, https://eu.i.posthog.com/batch/ or your own
    instrument: NoOpInstrument(),  // so no trace context goes to PostHog in the header fields
    encoder: PostHogBatchEncoder(projectToken: projectToken, plan: plan))
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
only a hand-written `BinaryCodable` conformance can write, and `distinct_id`) are left out and
logged. Like the collector's encoder, it leaves out a record the plan doesn't describe, one that
isn't `BinaryCodable` and one holding a value JSON can't, and also one whose event name starts with
`$`, as PostHog keeps those names for its own events. It logs each at error level, and
`batch(of:)` returns them as `PostHogSkippedRecord`s.

### Memory

To read what was tracked inside the app, deliver to an `InMemoryDestination` as well (module
``/Destinations``): for an event inspector in a debug build, a recent-activity view, a SwiftUI
preview, or a test of what your code tracks. It keeps the newest 1,000 records, or as many as you
pass as `capacity:`, dropping the oldest across batches; `InMemoryDestination.unbounded()` keeps
every one. Read it with `events(of: SignedUp.self)`, `records` or `batches`, or wait on
`deliveries`, which announces each batch to one reader.

### Sensitive values and call sites

A property that destinations shouldn't see unless they must is a `Sensitive` value. A destination
reads it only through the record, with `reveal(_:)`, and printing or mirroring it shows
`<redacted>`. `redactingSensitiveValues()` makes a destination's records reveal nothing, and
`droppingCallSite()` removes their call sites. Every other destination receives both:

```swift
struct SignedIn: Event {
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
