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
reported on `DatabaseStore.dropReports`. Records are encoded as `SegmentStore` encodes them, and
the same events are kept: every `@Event` in the program and the library's own, or only the
`Codable` types `DatabaseStore(events:database:)` lists. Rows written by
Traffluent 0.0.44 or earlier, in an earlier encoding, aren't read: each is deleted when the store
opens and reported as `.undecodable`, or as `.versionMismatch` where its stored version differs
from its type's.

How durable a commit is against power loss is the database's choice, through its journal mode and
`synchronous` setting. `DatabaseStore.synchronize()` checkpoints a database in WAL mode; call it
as the app moves to the background. Open one store per table at a time, and don't open one from
inside an access to the same database.

Once a delivered record's row is deleted, and in WAL mode once a later `synchronize()` succeeds,
nothing of it is left in the database's main file or its `-wal` file. The store's deletes run
with SQLite's `secure_delete` ON and its inserts with at least FAST, so freed pages and moved rows
are zeroed, and the app's own setting is put back after each. In WAL mode, `synchronize()`
truncates the log, which until then holds the deleted rows' earlier bytes. While another
connection reads or writes the database, such as a `DatabasePool` read whose transaction is still
open, the log can't be truncated, and the delivered records' bytes, `Sensitive` values and session
included, stay in the `-wal` file until a later `synchronize()` runs after that connection is
done. Inside a transaction, `synchronize()` checkpoints nothing.

Nothing is promised outside those two files: a `-journal` the app keeps with
`journal_mode=PERSIST` can hold earlier rows' bytes, and the file system may keep the blocks a
truncated or deleted file gave up. `DatabaseStore`'s documentation covers how long
`synchronize()` waits under each busy mode, and how a `DatabasePool` empties the log itself.

An app with no database of its own uses `SegmentStore`, which needs no GRDB.

```swift
import GRDB
import GRDBPersistence

let database = try DatabaseQueue(path: databasePath)
let store = try DatabaseStore(database: database, table: "analyticsRecord")
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
