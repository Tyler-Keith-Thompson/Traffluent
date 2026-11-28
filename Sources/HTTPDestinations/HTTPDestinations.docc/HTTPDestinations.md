# ``HTTPDestinations``

Send each batch of records to an HTTP endpoint, and send it again until it arrives.

## Overview

``HTTPDestination`` is a destination that posts each batch it receives as the requests its
``BatchEncoder`` splits it into: one request for an endpoint without limits. Each body is whatever
the encoder writes for its records, so events need no `Codable` conformance and the wire format is
yours. It sends with `URLSession` through
``URLSessionTransport`` by default, or through any ``HTTPTransport`` you pass.

A send that gets no response, or a 5xx, 408 or 429 status, is sent again after the next wait of its
``ExponentialBackoff``: nominally 1 second, doubling up to 60 seconds, unless you pass another. So
is one answered with a status the encoder lists in ``BatchEncoder/transientStatuses``, which every
encoder declares: empty for most servers, or each other failure its vendor answers to a request
worth sending again, such as Aptabase's 418 for a slow upload.

Each wait has full jitter by default: a random wait shorter than the nominal one, so apps refused
at the same moment retry at different moments. Pass ``ExponentialBackoff/Jitter/none`` for the
nominal waits. In tests, pass a seeded generator as `randomNumberGenerator:` for jittered waits
that repeat from one run to the next, as long as one request retries at a time: copies of a
destination retrying at once share the generator's draws in the order they ask for them. Never
seed it in production, where every device would then wait the same, which defeats the jitter. The
destination takes the next batch only once this one is delivered or dropped, so a tracker's store
keeps the batch's records until then. A batch the endpoint answers with any other status, whose
request can never be sent, or that the encoder can't encode is dropped, logged and reported on
``HTTPDestination/dropReports`` as an ``HTTPDropReport``, as is each record the encoder leaves out
of its requests. So is a request still undelivered at its ``EncodedRequest/deadline``, which an
encoder sets for a vendor that misdates or ignores old events: the destination checks it on its
`now:` clock before every attempt and sends nothing more once it has passed.

The tracing instrument injects the trace context of each request's first record into its header
fields, and `Content-Type` is always the encoder's.

Reach for this module to send to a server whose format you write yourself. For TraffluentCollector's
format, give the destination a `CollectorBatchEncoder` (module `CollectorEncoding`); for PostHog,
make it with `HTTPDestination.postHog(projectToken:host:plan:)` (module `PostHogEncoding`); for
Amplitude, with `HTTPDestination.amplitude(apiKey:region:plan:)` (module `AmplitudeEncoding`); for
Mixpanel, with `HTTPDestination.mixpanel(projectToken:region:plan:)` (module `MixpanelEncoding`);
for Segment, RudderStack or Customer.io Data Pipelines, with
`HTTPDestination.segment(writeKey:region:plan:)`, `rudderStack(writeKey:dataPlane:plan:)` or
`customerIO(apiKey:region:plan:)` (module `SegmentSpecEncoding`); for Google Analytics 4, from a
server, with `HTTPDestination.googleAnalytics(measurementID:apiSecret:region:plan:)` (module
`GoogleAnalyticsEncoding`); for Snowplow, with
`HTTPDestination.snowplow(collector:vendor:appID:plan:)` (module `SnowplowEncoding`); for
TelemetryDeck, with `HTTPDestination.telemetryDeck(appID:namespace:testMode:plan:)` (module
`TelemetryDeckEncoding`); for Matomo, with
`HTTPDestination.matomo(url:siteID:dimensions:category:plan:)` (module `MatomoEncoding`); for
Heap, with `HTTPDestination.heap(appID:region:plan:)` (module `HeapEncoding`); for Aptabase, with
`HTTPDestination.aptabase(appKey:host:isDebug:plan:)` (module `AptabaseEncoding`). To read events
inside the app or in a test, use
`InMemoryDestination` (module `Destinations`) instead.

```swift
import HTTPDestinations

struct PlansEncoder: BatchEncoder {
    static let transientStatuses: Set<TransientStatus> = []

    func requests(for batch: [EventRecord]) -> BatchRequests<Never> {
        let plans = batch.compactMap { ($0.event as? SignedUp)?.plan }
        let body = EncodedBatch(body: Data(plans.joined(separator: "\n").utf8), contentType: "text/plain")
        return BatchRequests(requests: [EncodedRequest(body: body, recordIDs: batch.map(\.id))], skippedRecords: [])
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

### Splitting a batch into requests

- ``BatchRequests``
- ``EncodedRequest``
- ``SkippedRecord``

### Retrying a vendor's own statuses

- ``TransientStatus``
- ``InvalidTransientStatus``

### Waiting between attempts

- ``ExponentialBackoff``
- ``InvalidBackoff``
- ``NonPositiveRetry``

### Sending requests

- ``HTTPTransport``
- ``URLSessionTransport``
- ``HTTPTransportError``
