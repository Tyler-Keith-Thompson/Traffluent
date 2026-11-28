# ``CollectorEncoding``

Write batches of records in TraffluentCollector's ingest format, for an `HTTPDestination` to send,
and read them back into records on a server.

## Overview

``CollectorBatchEncoder`` is the `BatchEncoder` for a self-hosted TraffluentCollector's
`POST /v1/batches`. Give it to an `HTTPDestination` (module ``/HTTPDestinations``) as its encoder,
and pass the collector's API key to the destination as an `Authorization: Bearer` header field.

The body is JSON: one object per record, with the record's identifier (which a redelivered record
keeps), the event's name and version, its timestamp, whether it is redelivered, its properties and
its context.
Properties are read from the event's `Encodable` form, which `@Event` derives, through the
event's schema in the `TrackingPlan` the encoder is made with. The context holds the standard
context keys the record has values for, its session and sample rate, and its trace context. A
`Sensitive` value is written only while the record reveals it; once redacted, a `Sensitive`
property is left out, and an array's element, or a value inside a type the plan can't map, is
`null`.

A record the encoder can't write is left out and the rest of the batch is sent: one whose event and
version the plan doesn't describe, one whose event isn't `Encodable`, one holding a value
JSON can't, such as a NaN, and one whose timestamp has no ISO 8601 form (NaN, infinite, or more
than `Int64.max` milliseconds from 1970). ``CollectorBatchEncoder/requests(for:)`` returns each record left out
as a `SkippedRecord` (module ``/HTTPDestinations``), which the destination logs and reports on
its `dropReports`. When no record of a batch can be written, the destination sends nothing.
``CollectorBatchEncoder/batch(of:)`` returns the same body and skipped records without a
destination.

To send to a server of your own format, write a `BatchEncoder` of your own. To send to PostHog,
use `PostHogBatchEncoder` (module `PostHogEncoding`).

```swift
import CollectorEncoding
import HTTPDestinations
import TrackingPlans

let plan = try TrackingPlan()
let encoder = CollectorBatchEncoder(plan: plan)
let collector = HTTPDestination(
    endpoint: collectorURL,  // https://collector.example.com/v1/batches
    headerFields: [.authorization: "Bearer \(apiKey)"],
    encoder: encoder)
let delivery = tracker.records.batch().deliver(to: collector)
```

The guide [Choosing Destinations](https://tyler-keith-thompson.github.io/Traffluent/documentation/traffluent/choosingdestinations)
covers sending to the collector beside the other destinations.

### Reading batches back

``CollectorBatchDecoder`` reads a body the encoder wrote back into `EventRecord`s, for a server
that receives an app's batches and hands them to another destination, such as a relay in front
of Google Analytics. Make it with the plan the app's encoder was made with. It finds each record's
event type by name and version among the `@Event`s the server links, or among the types you list
(``CollectorBatchDecoder/init(plan:events:instrument:)``).

```swift
import CollectorEncoding
import TrackingPlans

let plan = try TrackingPlan()
let decoder = try CollectorBatchDecoder(plan: plan)
let batch = try decoder.batch(from: body)  // a body CollectorBatchEncoder wrote
await destination.receive(batch.records)
```

Each record keeps its identifier, timestamp (to the millisecond), event, redelivery flag and the
context the body holds: its session's `SessionKey`, its sample rate, the standard context and its
trace context, which the decoder's instrument extracts. Encoding the records again with an encoder
of the same plan writes the same bytes. A record the decoder can't read is left out and the rest
are read: one of an event it has no type for, one at a version it has no type for or the plan
doesn't describe, one missing a member or holding what the encoder never writes, and one with a
property the event's type can't read: a required `Sensitive` property a delivery redacted, an
array of non-optional `Sensitive` elements it redacted, or an integer outside its property's type.

Each record states its event's version, and is read into the decoder's type of that name and
version. Once an app raises an event's version, its releases still installed send the earlier
one, so the server keeps a type for each version the apps send. Two `@Event` types of one name
build only when the earlier one sits in a `private` or `fileprivate` scope, where the decoder and
`TrackingPlan()` still find it:

```swift
@Event(name: "checkout_started", version: 2)
struct CheckoutStarted {
    var items: Int
    var currency: String
}

// Version 1, which releases still installed send.
private enum EarlierVersions {
    @Event(name: "checkout_started")
    struct CheckoutStarted {
        var items: Int
    }
}
```

Declare the earlier version's type at file scope, as above, or `fileprivate` inside another type:
`@Event` can't expand inside a type that is a `private` member of another
([Defining Events](https://tyler-keith-thompson.github.io/Traffluent/documentation/traffluent/definingevents)).
Build any store in that program from an explicit list (`SegmentStore(events:)`): a store holds one
type per name, so `SegmentStore()` throws `duplicateEventName` there.

A record at a version the server has no type for is reported as `unknownVersion`. Apps built with
an earlier Traffluent send no version, and the decoder reads such a record at version 1, or at the
lowest version it has when it has no version 1. Those apps sent version 1 unless the event declared
another. A record one of them sent at a raised version is read at version 1 too: it is reported
as `undecodableProperty` when its properties don't fit that type, and is read as version 1 when
they fit.
``DecodedCollectorBatch/undecodedRecords`` holds a report of each, an ``UndecodedRecord`` whose
reason is a ``CollectorDecodingError``. A body that isn't a collector batch at all throws
``NotACollectorBatch``.

## Topics

### Encoding batches

- ``CollectorBatchEncoder``
- ``CollectorBatch``

### Records left out

- ``CollectorEncodingError``

### Decoding batches

- ``CollectorBatchDecoder``
- ``DecodedCollectorBatch``
- ``CollectorBatchDecoderError``
- ``NotACollectorBatch``

### Records that can't be read

- ``UndecodedRecord``
- ``CollectorDecodingError``
