# ``Traffluent``

Vendor-neutral analytics for Swift: typed events, tracked by a tracker and delivered in batches to any number of destinations.

## Overview

An event is a value conforming to `Event`. A `Tracker` is a value: tracking an event records it as an `EventRecord`, with its timestamp, the caller's `SourceLocation` and its `ServiceContext`, as one of the tracker's `records`. Delivering is a chain of operators over that sequence: Afluent's `batch(strategy:)` (or `batch()`, the default) gathers the records into batches, and `deliver(to:)` hands each batch to every destination, as a lazy unit of work. A `Destination` is a plain sink, narrowed or transformed by its modifiers: `accepting(_:)` for the consent categories it serves, `redactingSensitiveValues()` and `droppingCallSite()`. A tracker given a `Consent` delivers an event only once the user grants its `ConsentCategory`, holding it while undecided and dropping it when denied. `track` only queues an event, from any thread; a worker the tracker owns, never on the main actor, does the rest. A tracker given a `SegmentStore` writes each record to disk as its worker reaches it and delivers what an earlier run left first.

`import Traffluent` imports every module but ``/GRDBPersistence``, a product of its own for apps
that already use GRDB. Each module also has its own documentation and can be imported on its own.

```swift
import Traffluent

struct SignedUp: Event {
    var plan: String
}

let tracker = Tracker()
let delivery = tracker.records.batch().deliver(to: ConsoleDestination())
tracker.track(SignedUp(plan: "pro"))
await tracker.finish()
try await delivery.execute()
```

## Topics

### Essentials

- <doc:WhatGoesWhere>

### Modules

- ``/Events``
- ``/Trackers``
- ``/Destinations``
- ``/DestinationTesting``
- ``/LoggingDestinations``
- ``/TracingDestinations``
- ``/HTTPDestinations``
- ``/Persistence``
- ``/GRDBPersistence``
- ``/Checksums``
