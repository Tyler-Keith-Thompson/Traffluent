# ``HTTPDestinations``

Send each batch of records to an HTTP endpoint, and send it again until it arrives.

## Overview

``HTTPDestination`` is a destination that posts each batch it receives as one request. The body is
whatever its ``BatchEncoder`` writes for the batch's records, so events need no `Codable`
conformance and the wire format is yours. It sends with `URLSession` through
``URLSessionTransport`` by default, or through any ``HTTPTransport`` you pass.

A send that gets no response, or a 5xx, 408 or 429 status, is sent again after the next wait of its
``ExponentialBackoff``: 1 second, doubling up to 60 seconds, unless you pass another. The
destination takes the next batch only once this one is delivered or dropped, so a tracker's store
keeps the batch's records until then. A batch the endpoint answers with any other status, whose
request can never be sent, or that the encoder can't encode is dropped, logged and reported on
``HTTPDestination/dropReports`` as an ``HTTPDropReport``.

The tracing instrument injects the trace context of the batch's first record into the request's
header fields, and `Content-Type` is always the encoder's.

Reach for this module to send to a server whose format you write yourself. For TraffluentCollector's
format, give the destination a `CollectorBatchEncoder` (module `CollectorEncoding`); for PostHog, a
`PostHogBatchEncoder` (module `PostHogEncoding`). To read events inside the app or in a test, use
`InMemoryDestination` (module `Destinations`) instead.

```swift
import HTTPDestinations

struct PlansEncoder: BatchEncoder {
    func encode(_ batch: [EventRecord]) -> EncodedBatch {
        let plans = batch.compactMap { ($0.event as? SignedUp)?.plan }
        return EncodedBatch(body: Data(plans.joined(separator: "\n").utf8), contentType: "text/plain")
    }
}

let server = HTTPDestination(
    endpoint: endpointURL,
    headerFields: [.authorization: "Bearer \(token)"],
    encoder: PlansEncoder(),
    backoff: try ExponentialBackoff(initialDelay: .seconds(2), maximumDelay: .seconds(120)))
let drops = server.dropReports
let watching = Task {
    for await drop in drops {
        print("Dropped a batch: \(drop)")
    }
}
let delivery = tracker.records.batch().deliver(to: server)
```

The guide [Choosing Destinations](https://tyler-keith-thompson.github.io/Traffluent/documentation/traffluent/choosingdestinations)
covers this destination beside the others, and what a delivery does while a batch is retried.

## Topics

### Sending batches

- ``HTTPDestination``
- ``HTTPDropReport``

### Encoding a batch

- ``BatchEncoder``
- ``EncodedBatch``

### Waiting between attempts

- ``ExponentialBackoff``
- ``InvalidBackoff``
- ``NonPositiveRetry``

### Sending requests

- ``HTTPTransport``
- ``URLSessionTransport``
- ``HTTPTransportError``
