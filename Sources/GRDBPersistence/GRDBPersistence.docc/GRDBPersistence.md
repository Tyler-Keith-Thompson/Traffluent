# ``GRDBPersistence``

Keep each record in a table of the app's own GRDB database until it is delivered.

## Overview

`DatabaseStore` is a `RecordStore` (module ``/Persistence``) for apps on Apple platforms that
already keep a GRDB database. It takes the app's `DatabaseQueue` or `DatabasePool` and a table
name, creates the table with a migration of its own, and opens no second SQLite database. It is a
product of its own, which `import Traffluent` leaves out.

It makes the same promises as `SegmentStore`. The tracker's worker commits each record, in a
transaction of its own, before publishing it. A batch's rows are marked before any destination
receives it and deleted once every destination has. The table holds at most `byteBound` bytes of
encoded records, 5 MiB by default, with the oldest rows deleted to make room, and each drop is
reported on `DatabaseStore.dropReports`. Records are encoded as `SegmentStore` encodes them, so
only events of the types in `events`, which conform to `BinaryCodable`, are kept.

How durable a commit is against power loss is the database's choice, through its journal mode and
`synchronous` setting. `DatabaseStore.synchronize()` checkpoints a database in WAL mode; call it
as the app moves to the background. Open one store per table at a time, and don't open one from
inside an access to the same database.

An app with no database of its own uses `SegmentStore`, which needs no GRDB.

```swift
import GRDB
import GRDBPersistence

let database = try DatabaseQueue(path: databasePath)
let store = try DatabaseStore(events: [SignedUp.self], database: database, table: "analyticsRecord")
let tracker = Tracker(store: store)
let delivery = tracker.records.batch().deliver(to: vendor)
tracker.track(SignedUp(plan: "pro"))
```

The guide [Persisting Records](https://tyler-keith-thompson.github.io/Traffluent/documentation/traffluent/persistingrecords)
covers what a store keeps, its bounds and recovery.

## API

The documentation site is built on Linux, where this module's API isn't there, so its symbols
have no pages of their own here. Their doc comments are in the sources, and Xcode shows them
for an Apple target.

### Keeping records in a database

- `DatabaseStore`
- `DatabaseStoreError`
