# ``AsyncQueues``

The sequence type of every report and delivery stream the library hands out, and of an app's own, read by one task at a time.

## Overview

``AsyncQueue`` is what a store's, a consent's, a tracker's, a delivery's and a destination's
report streams are: `SegmentStore.dropReports`, `DatabaseStore.dropReports`,
`Consent.dropReports`, `Tracker.rejectionReports`, `Tracker.samplingDropReports`,
`Delivery.bufferDropReports`, `HTTPDestination.dropReports` and
`InMemoryDestination.deliveries`. You read one with `for await`, as you would any asynchronous
sequence. The type that owns the queue fills it and ends it. Your code only reads these.

What arrives while nothing reads waits for the next read, as the owner's documentation says:
- A store's and an `HTTPDestination`'s drop reports wait without a bound.
- A delivery's buffer-drop reports merge into one per destination.
- A tracker's rejection reports merge into one per event, property and keyword.
- Its sampling drop reports merge into one per event type.
- A consent's drop reports merge only when a held-record-limit report follows another.
- An `InMemoryDestination` keeps only its newest batches.

The queue ends once its owner is gone or finished and every waiting element has been read.

One task reads at a time. The first iterator to read holds the queue until its iteration ends or
the iterator is released, as it is when its task ends. A holder that stops calling `next()` but
keeps its iterator keeps the turn. A second reader that starts meanwhile logs a warning once and
waits until the first one's iteration ends or its iterator is released, then reads on from the
next element. So the reader
holding the queue gets every element, in order, and nothing traps or takes elements from it. A
reader cancelled while it waits returns `nil` and leaves the holder alone. To hand every report to
several parts of the app, read the queue in one task and fan each report out from there.

```swift
let reports = store.dropReports
Task {
    for await report in reports {
        logger.warning("Dropped: \(report)")
    }
}
```

Read the queue into a constant before starting the task, as above, so the task holds the queue
and not its owner.

### A queue of your own

Where your app hands out a stream of its own, such as every report merged into one for its
logging, make it an `AsyncQueue` too, so a second reader of it waits its turn as with the
library's. ``AsyncQueue/Continuation`` is its writing end, as `AsyncStream.Continuation` is a
stream's: ``AsyncQueue/Continuation/init(name:)`` makes a queue that keeps what no one has read
yet without a bound, ``AsyncQueue/Continuation/enqueue(_:)`` adds an element from any thread
without waiting, and ``AsyncQueue/Continuation/finish()`` ends the queue after what it keeps, as
does the last copy of the continuation going away. Hand the readers
``AsyncQueue/Continuation/queue`` and keep the continuation to yourself:

```swift
let drops = AsyncQueue<String>.Continuation(name: "the app's drop reports")
let storeReports = store.dropReports
Task {
    for await report in storeReports {
        drops.enqueue("Not stored: \(report)")
    }
    drops.finish()
}
let reads = drops.queue
```

The umbrella guide on reading reports is
[Getting Started](https://tyler-keith-thompson.github.io/Traffluent/documentation/traffluent/gettingstarted).

## Topics

### Reading reports

- ``AsyncQueue``

### Making a queue of your own

- ``AsyncQueue/Continuation``
