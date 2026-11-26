# ``Destinations``

Where tracked events go: the `Destination` protocol, the modifiers that narrow what a destination receives, and the delivery that hands it batches.

## Overview

A ``Destination`` is a plain sink with one requirement, ``Destination/receive(_:)``, which is given
a batch of records, oldest first. Delivering is a chain of operators over a tracker's records:
`batch()` gathers them into batches of 20, and every 30 seconds while any are pending, and
`deliver(to:batchBufferLimit:bufferDropReporter:)` hands each batch to every destination as a
lazy unit of work that runs once you call `execute()`.

Each destination receives its batches in order, one at a time, from a buffer of its own, so a
slow one delays only itself. A full buffer drops its oldest batch and reports it as a
``BufferDropReport``. When the tracker has a store, the delivery reads the dropped batch's records
back for that destination once it catches up, and tells the store when each batch has reached
every destination.

What a destination receives is narrowed by modifiers: ``Destination/accepting(_:)`` for the
consent categories it serves, ``Destination/redactingSensitiveValues()`` and
``Destination/droppingCallSite()``, and added to by ``Destination/enriched(by:)``, which runs an
``/Events/Enricher`` on the records that destination alone receives. ``ConsoleDestination``
prints each event, and ``InMemoryDestination`` keeps the newest records it receives for the app to
read, in a debug view or a test.

Logs, traces and servers have destinations in modules of their own, so an app links only the ones
it uses: `LoggerDestination` in `LoggingDestinations`, `SpanEventDestination` in
`TracingDestinations` and `HTTPDestination` in `HTTPDestinations`.

```swift
struct Uploader: Destination {
    func receive(_ batch: [EventRecord]) async {
        // Send the batch, and return once it is somewhere it won't be lost.
    }
}

let inspector = try InMemoryDestination(capacity: 500)
let tracker = Tracker()
let delivery = tracker.records
    .batch(strategy: .count(20))
    .deliver(
        to: Uploader().accepting(.analytics).redactingSensitiveValues().droppingCallSite(),
        inspector
    )
tracker.track(SignedUp(plan: "pro"))
await tracker.finish()
try await delivery.execute()
let received = inspector.events(of: SignedUp.self)  // [SignedUp(plan: "pro")]
```

The umbrella guide on this area is
[Choosing Destinations](https://tyler-keith-thompson.github.io/Traffluent/documentation/traffluent/choosingdestinations).

## Topics

### Destinations

- ``Destination``
- ``ConsoleDestination``
- ``InMemoryDestination``
- ``InvalidCapacity``

### Delivering

- ``_Concurrency/AsyncSequence/batch(clock:)``
- ``_Concurrency/AsyncSequence/deliver(to:bufferDropReporter:)``
- ``_Concurrency/AsyncSequence/deliver(to:batchBufferLimit:bufferDropReporter:)``
- ``InvalidBatchBufferLimit``
- ``BufferDropReport``
