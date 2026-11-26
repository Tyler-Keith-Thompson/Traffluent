# ``Persistence``

Keep each record on disk until it is delivered, so the records a tracker tracked survive the app ending.

## Overview

Without a store, a tracker keeps its records in memory only. A tracker given a ``RecordStore``
(`Tracker(store:)`) appends each record to it as the tracker's worker reaches the record, before
publishing it, and starts its records with the ones the store kept from earlier runs.
``SegmentStore`` is the store this module ships: a directory of append-only segment files, bounded at 5 MiB unless you pass another `byteBound`. A segment is
deleted once every record in it is delivered.

A store keeps only the event types you list in `events`, which conform to ``BinaryCodable``:
CBOR (RFC 8949), each event a map of its properties under their names, written with a
``BinaryEncoder`` and read with a ``BinaryDecoder``. `@Event` (module `EventMacros`, part of
`import Traffluent`) writes the conformance; ``BinaryCodable`` shows one written by hand. Events of
other types are delivered in this run but never written.

Each drop is reported on ``SegmentStore/dropReports`` as a ``DropReport``: the oldest segments
deleted to stay under the bound, a write that failed, and records recovery couldn't read or found
at another `schemaVersion`. A record whose delivery had started when the app ended comes back with
`isRedelivered` set. Call ``SegmentStore/synchronize()``, after the tracker's `flush()`, as the
app moves to the background, so the records written so far survive power loss too.

An app on Apple platforms that already keeps a GRDB database can keep its records in a table of it
with `DatabaseStore` (module `GRDBPersistence`).

```swift
import Traffluent

@Event(name: "signed_up")
struct SignedUp {
    var plan: String
    var seats: Int = 1
}

let store = try SegmentStore(events: [SignedUp.self], directory: directory, byteBound: 1024 * 1024)
let tracker = Tracker(store: store)
let delivery = tracker.records.batch().deliver(to: vendor)
tracker.track(SignedUp(plan: "pro", seats: 3))
```

The guide [Persisting Records](https://tyler-keith-thompson.github.io/Traffluent/documentation/traffluent/persistingrecords)
covers what the store writes, its bounds and recovery, and
[Changing Events](https://tyler-keith-thompson.github.io/Traffluent/documentation/traffluent/changingevents)
covers which changes to an event's type its stored records can be read through.

## Topics

### Stores

- ``RecordStore``
- ``SegmentStore``
- ``DropReport``

### The binary encoding

- ``BinaryCodable``
- ``BinaryEncoder``
- ``KeyedBinaryEncoder``
- ``BinaryDecoder``
- ``KeyedBinaryDecoder``
- ``BinaryDecodingError``
