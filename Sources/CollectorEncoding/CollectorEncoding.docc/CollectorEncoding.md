# ``CollectorEncoding``

Write batches of records in TraffluentCollector's ingest format, for an `HTTPDestination` to send.

## Overview

``CollectorBatchEncoder`` is the `BatchEncoder` for a self-hosted TraffluentCollector's
`POST /v1/batches`. Give it to an `HTTPDestination` (module ``/HTTPDestinations``) as its encoder,
and pass the collector's API key to the destination as an `Authorization: Bearer` header field.

The body is JSON: one object per record, with the record's identifier (which a redelivered record
keeps), the event's name, its timestamp, whether it is redelivered, its properties and its context.
Properties are read from the event's `BinaryCodable` form, which `@Event` derives, through the
event's schema in the `TrackingPlan` the encoder is made with. The context holds the standard
context keys the record has values for, its session and sample rate, and its trace context. A
`Sensitive` value is written only while the record reveals it.

A record the encoder can't write is left out and the rest of the batch is sent: one whose event and
version the plan doesn't describe, one whose event isn't `BinaryCodable`, and one holding a value
JSON can't, such as a NaN. Each is logged; ``CollectorBatchEncoder/batch(of:)`` returns the body
with each record left out as a ``SkippedRecord``. When no record of a batch can be written,
``CollectorBatchEncoder/encode(_:)`` throws, and the destination sends nothing.

To send to a server of your own format, write a `BatchEncoder` of your own. To send to PostHog,
use `PostHogBatchEncoder` (module `PostHogEncoding`).

```swift
import CollectorEncoding
import HTTPDestinations
import TrackingPlans

let plan = TrackingPlan(schemas: [SignedUp.schema])
let encoder = CollectorBatchEncoder(plan: plan)
let collector = HTTPDestination(
    endpoint: collectorURL,  // https://collector.example.com/v1/batches
    headerFields: [.authorization: "Bearer \(apiKey)"],
    encoder: encoder)
let delivery = tracker.records.batch().deliver(to: collector)
```

The guide [Choosing Destinations](https://tyler-keith-thompson.github.io/Traffluent/documentation/traffluent/choosingdestinations)
covers sending to the collector beside the other destinations.

## Topics

### Encoding batches

- ``CollectorBatchEncoder``
- ``CollectorBatch``

### Records left out

- ``SkippedRecord``
- ``CollectorEncodingError``
