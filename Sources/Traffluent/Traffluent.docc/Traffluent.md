# ``Traffluent``

Vendor-neutral analytics for Swift: typed events, tracked by a tracker and delivered in batches to any number of destinations.

## Overview

An event is a value conforming to `Event`. A `Tracker` is a value: tracking an event records it as an `EventRecord`, with its timestamp, the caller's `SourceLocation` and its `ServiceContext`, as one of the tracker's `records`. Delivering is a chain of operators over that sequence: Afluent's `batch(strategy:)` (or `batch()`, the default) gathers the records into batches, and `deliver(to:)` hands each batch to every destination, as a lazy unit of work. A `Destination` is a plain sink.

`import Traffluent` imports every module. Each module also has its own documentation and can be
imported on its own.

```swift
import Traffluent

struct SignedUp: Event {
    var plan: String
}

let tracker = Tracker()
let delivery = tracker.records.batch().deliver(to: ConsoleDestination())
tracker.track(SignedUp(plan: "pro"))
tracker.finish()
try await delivery.execute()
```

## Topics

### Modules

- ``/Events``
- ``/Trackers``
- ``/Destinations``
- ``/DestinationTesting``
- ``/LoggingDestinations``
- ``/TracingDestinations``
