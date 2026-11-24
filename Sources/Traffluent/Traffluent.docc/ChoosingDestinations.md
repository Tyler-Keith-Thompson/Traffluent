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
Other destinations aren't held up. Meanwhile the delivery's later batches wait in this
destination's buffer of `batchBufferLimit` batches, which drops its oldest when full; a store keeps
the records of a dropped batch for the next launch.

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
