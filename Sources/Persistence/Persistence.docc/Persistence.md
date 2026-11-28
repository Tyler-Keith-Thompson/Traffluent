# ``Persistence``

Keep each record on disk until it is delivered, so the records a tracker tracked survive the app ending.

## Overview

Without a store, a tracker keeps its records in memory only. A tracker given a ``RecordStore``
(`Tracker(store:)`) appends each record to it as the tracker's worker reaches the record, before
publishing it, and starts its records with the ones the store kept from earlier runs.
``SegmentStore`` is the store this module ships: a directory of append-only segment files, bounded at 5 MiB unless you pass another `byteBound`. A segment is
deleted once every record in it is delivered.

`SegmentStore()` keeps every event type declared with `@Event` in the program's modules, and the
library's own; `SegmentStore(events:)` keeps only the `Codable` types it lists. Each record
is a CBOR (RFC 8949) map, its event a map of its properties under their names, written through the
event's `Codable` conformance. `@Event` (module `EventMacros`, part of `import Traffluent`) writes
the conformance, and Swift's synthesized one works too. `@Event` writes a `Date` property, and each
date in a `[Date]` or `[Date?]`, as the seconds since 2001 it stores, so it reads back exactly. A
`Date` written through the CBOR package's own form, in a `Codable` type of your own or in a
synthesized conformance, reads back to within a rounding of a microsecond's scale. Events of other
types, such as one that conforms to `Event` by hand without being listed, are delivered in this
run but never written, and reported once as ``DropReport/notPersisted(event:)``.

A record keeps its session, sample rate, screen and standard context (app, device, operating
system, locale and network) beside it, so a record recovered after a relaunch reaches destinations
as it was tracked. No other key of its context is kept: not the identifier for vendor, a key of
the app's own, or the trace. ``SegmentStore`` lists each key.

A store doesn't read the records Traffluent 0.0.44 or earlier wrote, in an earlier format:
``SegmentStore`` deletes their segments and reports each as a corruption.

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

let store = try SegmentStore(directory: directory, byteBound: 1024 * 1024)
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
- ``SegmentStoreError``
- ``DropReport``

