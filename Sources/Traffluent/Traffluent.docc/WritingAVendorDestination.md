# Writing a Vendor Destination

Send events to an analytics vendor Traffluent doesn't cover yet, from a module of your own, with the same rules as the destinations it ships.

## Overview

A vendor destination is an `HTTPDestination` with an encoder that writes the vendor's ingestion
format. `HTTPDestination` already does the batching, retries, drop reports and trace context, so the
vendor module adds three things:

- an encoder, a `BatchEncoder` that writes each record as the vendor's JSON and splits a batch to
  the vendor's limits;
- a factory on `HTTPDestination` that checks what the adopter passes and fills in the endpoint, the
  encoder and the limits, so setup is one call;
- tests that run `DestinationTesting`'s conformance checks and compare its requests with recorded
  fixtures.

Write the encoder against the vendor's public HTTP API, not its SDK, so the app links nothing of
the vendor's. ``/PostHogEncoding`` is built this way and is a full example to copy.

### The module

Make the module depend on `HTTPDestinations`, `PropertyJSON`, `JSONValues` and `TrackingPlans`,
and on swift-distributed-tracing's `Instrumentation` for `NoOpInstrument`. Its tests depend on
`DestinationTesting` as well. `PropertyJSON` holds the vendor-neutral pieces an encoder is built
from, `JSONValues` the `JSON` value it writes, and `TrackingPlans` the app's `TrackingPlan`, which
the encoder reads properties through. `DestinationTesting` imports Swift Testing, so it goes in
test targets only.

```swift
.target(name: "AcmeEncoding", dependencies: [
    .product(name: "HTTPDestinations", package: "Traffluent"),
    .product(name: "PropertyJSON", package: "Traffluent"),
    .product(name: "JSONValues", package: "Traffluent"),
    .product(name: "TrackingPlans", package: "Traffluent"),
    .product(name: "Instrumentation", package: "swift-distributed-tracing"),
]),
.testTarget(name: "AcmeEncodingTests", dependencies: [
    "AcmeEncoding",
    .product(name: "DestinationTesting", package: "Traffluent"),
], resources: [.copy("Fixtures")]),
```

### The encoder

The examples here are for Acme, a made-up vendor whose API takes
`{"api_key": …, "events": [{"event", "user_id", "insert_id", "time", "properties", "context"}]}`
and allows at most 500 events and 1,000,000 bytes a request, and 32,000 bytes an event.
`PropertyJSON` supplies each piece of such a record:

- `PropertyReader` reads an event's properties through its schema in the app's `TrackingPlan`,
  leaving out `Sensitive` values unless you ask for them and the record reveals them.
- `EventRecord.standardContext` is the app, device, locale, network and operating system as JSON,
  and `flattened(separator:)` turns it into the one level of dotted keys most vendors take.
- `Date.iso8601Timestamp` and `Date.millisecondsSince1970()` are the two timestamp formats vendors
  ask for.
- `EventRecord.pseudonymousIdentity` is who the event is about: the record's session, or the record
  itself when it has none, and never a person (<doc:IdentifyingPeople>). `deduplicationID` is the
  identifier a vendor drops repeats by, which a redelivered record keeps.
- `BatchLimit.requests(for:in:encoding:oversized:)` splits a batch into requests of a
  `JSONEnvelope` within the vendor's limits, and leaves out a record that fits in none of them.

```swift
/// Why the Acme encoder left a record out.
enum AcmeEncodingError: Error, Hashable {
    case unreadable(PropertyReadingError)
    case contextKeyCollision(key: String)
    case unrepresentableTimestamp
    case oversized(byteCount: Int)
}

struct AcmeBatchEncoder: BatchEncoder {
    /// Acme's limits on one request.
    static let batchLimit = (try? BatchLimit(maximumRecordCount: 500, maximumByteCount: 1_000_000, maximumRecordByteCount: 32_000)) ?? .unlimited

    typealias Failure = AcmeEncodingError

    private let reader: PropertyReader
    private let envelope: JSONEnvelope

    init(apiKey: String, plan: TrackingPlan) {
        reader = PropertyReader(plan: plan)
        envelope = JSONEnvelope(["api_key": .string(apiKey)], arrayMember: "events")
    }

    func requests(for batch: [EventRecord]) -> BatchRequests<AcmeEncodingError> {
        Self.batchLimit.requests(for: batch, in: envelope) { record throws(AcmeEncodingError) in
            try json(of: record)
        } oversized: { byteCount in
            .oversized(byteCount: byteCount)
        }
    }

    private func json(of record: EventRecord) throws(AcmeEncodingError) -> JSON {
        let properties: [String: JSON]
        do {
            properties = try reader.properties(of: record, includingSensitiveValues: false)
        } catch {
            throw .unreadable(error)
        }
        let context: [String: JSON]
        do {
            context = try record.standardContext.flattened()
        } catch {
            throw .contextKeyCollision(key: error.key)
        }
        let time: Int64
        do {
            time = try record.timestamp.millisecondsSince1970()
        } catch {
            throw .unrepresentableTimestamp
        }
        return .object([
            "event": .string(record.name),
            "user_id": .string(record.pseudonymousIdentity.uuid.uuidString.lowercased()),
            "insert_id": .string(record.deduplicationID),
            "time": .integer(time),
            "properties": .object(properties),
            "context": .object(context),
        ])
    }
}
```

`requests(for:)` is all a `BatchEncoder` implements, and `Failure` names the reason a record is
left out, as `requests(for:)` doesn't throw. `HTTPDestination` sends the requests in order, and
reports each record left out as `HTTPDropReport.skipped(_:)`. Pass `includingSensitiveValues: true` only if the
vendor's terms allow the values, and then only through a factory the adopter opts in with.

If the vendor misdates or ignores an event past some age but still answers 2xx, pass an age a
little short of it to `limit.requests(for:in:maximumAge:encoding:oversized:)`, which throws
`NegativeMaximumAge` for one below zero. The spare time covers a request's trip to the vendor and
clocks that disagree. Each request then has a deadline that long after its oldest record was
tracked, and `HTTPDestination` drops a request still being retried by then, all of its records, and
reports it as `HTTPDropReport.deadlineExceeded(deadline:recordIDs:)`, rather than send records the
vendor would store wrongly. Have the factory pass its `now:` to both the encoder and the
destination, so one clock decides what is encoded and what is sent.

### The factory

The factory is a static method on `HTTPDestination` constrained to the encoder, so adopters write
`try HTTPDestination.acme(...)`. It throws a typed error for input the vendor would refuse, so a
mistake shows up at launch, not later as a stream of rejected requests. It also takes a transport
and a backoff, which the conformance checks need. It passes `NoOpInstrument()`, so no request
carries the app's trace context to the vendor, whatever tracer the app bootstraps.

```swift
/// Why the Acme factory couldn't make a destination.
enum AcmeSetupError: Error, Hashable {
    case emptyAPIKey
    case invalidHost
}

extension HTTPDestination where Encoding == AcmeBatchEncoder {
    static func acme(
        apiKey: String,
        host: URL,
        plan: TrackingPlan,
        transport: Transport,
        backoff: ExponentialBackoff = ExponentialBackoff()
    ) throws(AcmeSetupError) -> HTTPDestination<Transport, AcmeBatchEncoder> {
        guard !apiKey.isEmpty else { throw .emptyAPIKey }
        guard host.scheme == "https", host.host() != nil else { throw .invalidHost }
        return HTTPDestination(
            endpoint: host.appending(path: "v1/events"),
            // Acme doesn't read a trace context, so the app's traces aren't sent to it.
            instrument: NoOpInstrument(),
            transport: transport,
            encoder: AcmeBatchEncoder(apiKey: apiKey, plan: plan),
            backoff: backoff)
    }
}
```

Offer an overload without `transport:` that passes `URLSessionTransport()`, as PostHog's does, so
an app needn't name one.

### The conformance checks

`DestinationConformance` runs the checks every vendor destination must pass. Give it the vendor's
limit and a closure that calls the factory with the setup's plan, transport and backoff:

- ``/DestinationTesting/ConformanceCheck/sensitiveValuesRedacted``: no `Sensitive` value is sent
  without the adopter's opt-in.
- ``/DestinationTesting/ConformanceCheck/consentHolds``: behind consent and `accepting(_:)`, the
  destination sends exactly the records it is handed.
- ``/DestinationTesting/ConformanceCheck/oversizedRecordSkipped``: a record over the limit is
  skipped and reported.
- ``/DestinationTesting/ConformanceCheck/transientFailuresRetried`` and
  ``/DestinationTesting/ConformanceCheck/rejectionsDropped``: failures are retried or dropped as
  `HTTPDestination` classifies them.
- ``/DestinationTesting/ConformanceCheck/traceContextWithheld``: no request carries a trace context,
  even while a tracer is active.

`expectRequests(of:plan:matchFixture:withExtension:subdirectory:in:sourceLocation:)` compares the
requests a hand-worked batch makes with a fixture in the test target's resources, byte for byte.
When the fixture is missing, the issue it records holds the requests, so you can check them by hand
against the vendor's documentation and save them as the fixture.

```swift
@Test(arguments: ConformanceCheck.allCases)
func acmeConformance(check: ConformanceCheck) async throws {
    let host = try #require(URL(string: "https://acme.example.com"))
    let conformance = DestinationConformance(limit: AcmeBatchEncoder.batchLimit) { setup in
        try HTTPDestination.acme(apiKey: "test-key", host: host, plan: setup.plan, transport: setup.transport, backoff: setup.backoff)
    }
    try await conformance.expect(check)
}
```

Each check records a Swift Testing issue for each rule the destination breaks. The kit is a
shared assertion on purpose, so every vendor module runs the same checks. Every check's records are
tracked at `setup.timestamp`; if your encoder leaves out records older than the vendor takes, give
it that as the time it encodes at, as `GoogleAnalyticsEncoding`'s tests do.
