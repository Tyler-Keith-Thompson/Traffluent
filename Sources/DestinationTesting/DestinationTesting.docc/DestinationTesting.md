# ``DestinationTesting``

Check from Swift Testing that a vendor destination keeps the library's rules and sends what its fixtures record.

## Overview

``DestinationConformance`` runs the checks every vendor destination must pass, through a
``ScriptedTransport`` that keeps each request and answers from a script rather than the network:

- its requests match recorded fixtures byte for byte;
- a `Sensitive` value is sent only after the adopter opts in, and only while the record reveals it;
- behind a tracker's consent and `accepting(_:)`, it sends exactly the records it is handed;
- a record over the vendor's limit is left out and reported, and the rest of its batch is sent;
- no response, a 5xx, 408 and 429 are retried, and other failures are dropped and reported;
- no request carries a trace context in its header fields, even while a tracer is active.

Make it with the vendor's limit and a closure that calls the vendor's factory with the
``DestinationSetup``'s plan, transport and backoff. Every check's records are tracked at the
setup's `timestamp`; a factory whose encoder leaves out records by their age takes it as the time
it encodes at, so the checks pass whenever the test runs. Run each ``ConformanceCheck`` as a test
case of its own:

```swift
import DestinationTesting
import Foundation
import HTTPDestinations
import PostHogEncoding
import Testing

@Test(arguments: ConformanceCheck.allCases)
func postHogConformance(check: ConformanceCheck) async throws {
    let host = try #require(URL(string: "https://posthog.example.com"))
    let conformance = DestinationConformance(limit: PostHogBatchEncoder.batchLimit) { setup in
        try HTTPDestination.postHog(projectToken: "phc_test", host: host, plan: setup.plan, transport: setup.transport, backoff: setup.backoff)
    }
    try await conformance.expect(check)
}
```

Each check records a Swift Testing issue for every rule the destination breaks. A project's own
tests write their assertions out in full. This one is shared on purpose, as TrackingPlanTesting's
`expectTrackingPlan(_:matches:sourceLocation:)` is, so every vendor module runs the same checks.
It imports Swift Testing, so add it to test targets only. `import Traffluent` leaves it out.

The guide [Writing a Vendor Destination](https://tyler-keith-thompson.github.io/Traffluent/documentation/traffluent/writingavendordestination)
covers the module these checks test.

## Topics

### Checking a destination

- ``DestinationConformance``
- ``ConformanceCheck``
- ``DestinationSetup``

### Sending without a network

- ``ScriptedTransport``
