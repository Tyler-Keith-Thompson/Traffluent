# Tracking Events

Track typed events with a tracker, then deliver them in batches to any number of destinations.

## Overview

An event is a value that conforms to `Event`, declared with `@Event`. A `Tracker` records each
event you track, and a delivery hands the records to your destinations:

```swift
import Traffluent

@Event
struct SignedUp {
    var plan: String
}

let tracker = Tracker()
let delivery = tracker.records.batch().deliver(to: ConsoleDestination())
tracker.track(SignedUp(plan: "pro"))
await tracker.finish()
try await delivery.execute()  // prints: SignedUp SignedUp(plan: "pro")
```

`track` returns at once, from any thread, the main thread included. It reads the clock, captures
the call site and the task's `ServiceContext`, and queues them. A worker the tracker owns, never on
the main actor, does the rest in the order events were tracked, so no enricher, consent check,
encoding or disk write runs on the caller. The worker records the event as an `EventRecord`, with
the time it was tracked and the caller's file, module, function, line and column, and adds the
record to the tracker's `records`, an `AsyncSequence`.

Delivering is a chain of operators over that sequence. `batch()` gathers the records into batches
of 20, or every 30 seconds while any are waiting, and `deliver(to:)` hands each batch to every
destination. The chain is a lazy Afluent unit of work: nothing runs until `execute()`. Run it for as
long as the app tracks events. `finish()` waits for the worker to catch up, then ends the records,
so the delivery sends what is still pending and completes. Records tracked before the delivery
starts, or between two deliveries, wait for the next one, so none is lost.

### Batching

Batching is Afluent's `batch(strategy:)`, so any of its strategies, or one of your own, decides
when a batch goes out:

```swift
let delivery = tracker.records
    .batch(strategy: .either(.count(50), .time(interval: .seconds(10), clock: ContinuousClock())))
    .deliver(to: ConsoleDestination(), batchBufferLimit: 10)
```

`batch(clock:)` takes the clock that the default's 30 seconds run on. `Tracker(now:)` takes the
wall-clock source records are stamped with, the system's unless you pass another; tests pass a test
clock and fixed dates. Each destination receives its batches in order from a buffer of its own,
`batchBufferLimit` batches deep (100 by default), so a slow destination holds up only itself. When
its buffer is full, its oldest waiting batch is dropped and reported on the delivery's
`bufferDropReporter`, if you pass one. Once the destination catches up, the delivery reads that
batch's records back from the store and sends them to it (<doc:ChoosingDestinations>). A delivery
that finished or failed can be executed again, as a retry. Cancelling one is permanent, as it is for every Afluent unit of work, so
after a cancellation build a new delivery. It delivers every record the cancelled one hadn't read.

### Tracking from anywhere

Code deep in an app doesn't need to be handed the tracker. Bind it to a task with `withTracker`
and read it anywhere inside with `Tracker.current`:

```swift
let tracker = Tracker()
withTracker(tracker) {
    Tracker.current.track(SignedUp(plan: "pro"))
}
await tracker.finish()
try await tracker.records.batch().deliver(to: ConsoleDestination()).execute()  // prints: SignedUp SignedUp(plan: "pro")
```

The binding reaches child tasks, and a nested `withTracker` replaces it for its own scope. It
doesn't reach callbacks a framework runs on tasks of its own, such as SwiftUI button actions. Pass
those a `Tracker`, or in SwiftUI read it from the environment (<doc:TrackingFromViews>). With no
tracker bound, `Tracker.current` drops each event and logs it at debug level.

### Context and enrichers

Every record also carries the `ServiceContext` it was tracked in (the `Instrumentation` module of
swift-distributed-tracing). A destination reads it through typed keys, so it can see the session,
the screen or the active span's trace without a string-keyed bag. An `Enricher` adds to it as each
event is tracked:

```swift
import Instrumentation

enum ExperimentKey: ServiceContextKey {
    typealias Value = String
}

let experiment = Enricher { context in
    context[ExperimentKey.self] = "new-checkout"
}
let tracker = Tracker(enrichers: [experiment])
tracker.track(SignedUp(plan: "pro"))  // its record's context[ExperimentKey.self] is "new-checkout"
```

Where a task-local context doesn't reach, `tracker.enriched(by:)` gives one part of an app a copy
of the tracker whose events alone carry a value, such as a screen's name. The copy shares the
tracker's records, and the worker runs the copy's enricher before the tracker's own.

### Delivery guarantees

`track` only queues an event. A record exists, in `records` and in a store, once the tracker's
worker has reached it. `await tracker.flush()` waits until the worker has reached everything
tracked so far; `await tracker.finish()` does the same, then ends the records. Records waiting for
a delivery are held in memory without a bound. Records a delivery has read but not yet delivered
are lost to this run if the delivery is cancelled or fails. Without a store they are gone; with
one they come back on the next launch (<doc:PersistingRecords>). A batch dropped from a
destination's full buffer is reported; its stored records reach that destination later in the same
run, and the rest are lost. One task reads a tracker's records at a time: a second reader at the
same time traps.
