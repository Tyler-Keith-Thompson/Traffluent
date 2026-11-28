#if canImport(GRDB)
public import AsyncQueues
public import Events
public import GRDB
public import Persistence

/// A `RecordStore` that keeps records in a table of the app's own GRDB database, bounded in size,
/// until they are delivered.
///
/// ```swift
/// let database = try DatabasePool(path: databasePath)
/// let store = try DatabaseStore(database: database)
/// let tracker = Tracker(store: store)
/// let delivery = tracker.records.batch().deliver(to: vendor)
/// ```
///
/// For apps that already keep a GRDB database: the records live in a table of it, through the
/// app's own `DatabaseQueue` or `DatabasePool`, so the app opens no second SQLite database.
///
/// - **The table.** The store creates its table, with a migration of its own in a
///   `DatabaseMigrator`, the first time it opens a database. The migration's identifier,
///   `Traffluent.DatabaseStore.<table>.v1`, sits in the database's `grdb_migrations` table beside
///   the app's, which the app's migrator ignores. A migrator with `eraseDatabaseOnSchemaChange`
///   sees the store's table as a schema change and erases the database, records and all.
/// - **Write-through.** A tracker's worker inserts each record, in a transaction of its own, as
///   it reaches the record, off the tracking caller's thread, so the record survives the app
///   crashing or being killed once the transaction commits. How durable a commit is against power loss is the database's choice (its journal
///   mode and `synchronous` setting); ``synchronize()`` checkpoints a database in WAL mode, so
///   call it as the app moves to the background or terminates. A record whose insert fails is
///   kept in memory only, and reported as `DropReport.writeFailed(recordCount:timestamps:)`.
///   Tracking inside one of the app's own writes to the same database is allowed: the record
///   doesn't join the app's transaction, and the worker inserts it once that write is done, even
///   if it rolls back.
/// - **What is kept.** Every event `DiscoveredEvent.all` lists, or only the `Codable` types in
///   `events`, in the same encoding as `SegmentStore`'s. Events of any other type are kept in memory only:
///   they are delivered in this run like any other, are never written, and are lost if the app
///   ends first. The first record of each such type is reported as
///   `DropReport.notPersisted(event:)`, so a type left out by mistake shows up.
/// - **A recovered record's context.** A record keeps these keys of its context, written in its
///   row's bytes, so a record recovered after a relaunch reaches destinations as it was tracked:
///   - `SessionKey`, so a vendor destination sends it under the same identity as the first time;
///   - `SampleRateKey`, so it is weighted by the rate it was sampled at;
///   - `ScreenKey`, `ApplicationKey`, `DeviceKey`, `OperatingSystemKey`, `LocaleKey` and
///     `NetworkKey`, so it is attributed to where it was tracked, not to the run that uploads it.
///     A locale is kept as its identifier, so a preference the identifier doesn't spell is lost.
///
///   The store writes these keys whatever set them, so don't build a screen name, or an app or
///   device value, from user data.
///
///   A key the record didn't have comes back absent. No other key is kept, so a recovered record
///   is otherwise in the top-level `ServiceContext`: not `VendorIdentifierKey`, which Traffluent
///   never stores; not a key of the app's own, such as an account's, which the store can't tell
///   from an identifier; and not the trace context, as its span ended with the earlier run.
/// - **Deleting.** A record's row, its context included, is deleted once every destination has
///   received it, so a table whose records are all delivered is empty, and the store keeps no
///   session apart from the records tracked in it. Once a deletion commits, and in WAL mode once
///   a later ``synchronize()`` succeeds, nothing of the deleted rows is left in the database's
///   main file or its `-wal` file. The store's deletes run with SQLite's `secure_delete` ON, so
///   the pages they free are zeroed, and its inserts with at least FAST, so a page they split
///   keeps no old copy of a row; whatever the app set is put back after each, and the app's own
///   tables are left to it.
///
///   Outside those two files the store promises nothing. A rollback journal the app keeps with
///   `journal_mode=PERSIST` holds the pages a transaction changed, earlier rows' bytes among them,
///   until a later transaction writes over them. And the file system may keep the blocks a
///   truncated or deleted file gave up (the `-wal` after a checkpoint, a `-journal` after a
///   commit) until it reuses them; nothing wipes those.
///
///   In WAL mode the log keeps a deleted row's earlier bytes until ``synchronize()``, which
///   checkpoints the log into the main file and truncates it to nothing. While another connection
///   reads or writes the database (a `DatabasePool` read with its transaction still open, a
///   `DatabaseSnapshot`, an app extension), the log can't be truncated: ``synchronize()`` copies
///   what it can, logs a notice and returns, and the delivered rows' bytes, `Sensitive` values and
///   session included, stay in the `-wal` file until a later ``synchronize()`` runs once those
///   connections are done. Called inside a transaction, ``synchronize()`` checkpoints nothing at
///   all and logs a notice, so call it outside the app's own writes. To empty the log on the
///   app's own schedule, a `DatabasePool` can run
///   `try pool.barrierWriteWithoutTransaction { try $0.checkpoint(.truncate) }`, which waits for
///   the pool's reads to end and throws a `DatabaseError` with `SQLITE_BUSY` while another
///   connection still uses the log.
///
///   ``synchronize()`` waits for other connections only as long as the database's busy mode lets
///   it. GRDB's default, `immediateError`, doesn't wait. Under `.timeout(t)` it waits up to `t`
///   while a reader is open, and holds the database's writer meanwhile, so the app's writes wait
///   with it. Under a `.callback` that always retries, it waits until every reader is done, which
///   may be never; don't give the database such a handler.
/// - **Reading back.** When a destination's full buffer drops a batch on its way through a
///   delivery, the delivery reads that batch's rows back, in one read, once the destination has
///   caught up, and hands their records to it in this run, each in the context it was tracked in,
///   which the delivery keeps. A row the bound deleted in the meantime isn't read back, and one
///   that can't be decoded is logged and waits for a later launch.
/// - **Bound.** The table never holds more than `byteBound` bytes of encoded records (each
///   row's payload; SQLite's own pages and indexes come on top). When a record wouldn't fit, the
///   oldest rows are deleted until it does, in the same transaction as the insert, and each
///   insert that deletes rows yields a `DropReport.sizeBound(recordCount:timestamps:)` on
///   ``dropReports``. A record too large for an empty table is kept in memory only.
/// - **Recovery.** A store opened on a table recovers the records earlier runs left there, and a
///   tracker given the store delivers them first. A row whose record can't be decoded (its event
///   type isn't in `events`, or its decoding throws) is deleted and reported as
///   `DropReport.undecodable(recordCount:)`, and one stored at another `Event.schemaVersion` than
///   its type's now is deleted without being read and reported as
///   `DropReport.versionMismatch(event:storedVersion:currentVersion:recordCount:)`. Each record a delivery had started on comes back with
///   `isRedelivered` set, as it may have reached a destination already. A delivery marks a
///   batch's rows, in one transaction, before any destination receives it; a batch whose mark
///   can't be written is held back from that delivery, so it is never sent twice unannounced, and
///   delivered on a later launch.
///
/// Open one store per table at a time; two would delete each other's rows. Don't open a store
/// from inside an access to the same database: GRDB's migrations aren't reentrant. Copies of a
/// store share its table.
public struct DatabaseStore: RecordStore {
    /// The bound a store has unless it is given another: 5 MiB (5,242,880 bytes) of encoded records.
    public static let defaultByteBound = 5 * 1024 * 1024

    /// The table a store keeps its records in unless it is given another.
    public static let defaultTable = "traffluentRecord"

    let log: DatabaseLog

    /// A store keeping events of the types `events` in `table` of `database`; it creates the
    /// table if it is missing, and recovers the records already there.
    ///
    /// - Parameters:
    ///   - events: The event types to keep. No two may share an `Event.name`.
    ///   - database: The app's database: a `DatabaseQueue` or a `DatabasePool`.
    ///   - table: The table the records go in; ``defaultTable`` unless given. It may not hold a
    ///     double quote.
    ///   - byteBound: The most bytes of encoded records the table may hold.
    /// - Throws: ``DatabaseStoreError/nonPositiveByteBound`` when `byteBound` isn't positive,
    ///   ``DatabaseStoreError/duplicateEventName(_:firstType:secondType:)`` when two of `events` share an `Event.name`,
    ///   and ``DatabaseStoreError/database(_:)`` when the table can't be created (the database is
    ///   read-only, or `table` holds a double quote) or read, or the rows recovery drops can't be
    ///   deleted.
    public init(
        events: [any (Event & Codable).Type],
        database: some DatabaseWriter,
        table: String = DatabaseStore.defaultTable,
        byteBound: Int = DatabaseStore.defaultByteBound
    ) throws(DatabaseStoreError) {
        guard byteBound > 0 else { throw .nonPositiveByteBound }
        let registry: EventRegistry
        do throws(DuplicateEventName) {
            registry = try EventRegistry(events)
        } catch {
            throw .duplicateEventName(error.name, firstType: error.firstType, secondType: error.secondType)
        }
        do throws(DatabaseError) {
            log = try DatabaseLog(writer: database, table: table, registry: registry, byteBound: byteBound)
        } catch {
            throw .database(error)
        }
    }

    /// A store keeping events of every type the program declares with `@Event`, and the
    /// library's own, in `table` of `database`; it creates the table if it is missing, and
    /// recovers the records already there.
    ///
    /// The types are `DiscoveredEvent.all`'s, found in every module the program links. An event
    /// that conforms to `Event` by hand isn't among them; to keep one too, list the types with
    /// ``init(events:database:table:byteBound:)``: `DiscoveredEvent.all.map(\.type) + [Legacy.self]`.
    ///
    /// - Parameters:
    ///   - database: The app's database: a `DatabaseQueue` or a `DatabasePool`.
    ///   - table: The table the records go in; ``defaultTable`` unless given. It may not hold a
    ///     double quote.
    ///   - byteBound: The most bytes of encoded records the table may hold.
    /// - Throws: ``DatabaseStoreError/nonPositiveByteBound`` when `byteBound` isn't positive,
    ///   ``DatabaseStoreError/duplicateEventName(_:firstType:secondType:)`` when two of the program's event types share an
    ///   `Event.name`, and ``DatabaseStoreError/database(_:)`` when the table can't be created (the
    ///   database is read-only, or `table` holds a double quote) or read, or the rows recovery
    ///   drops can't be deleted.
    public init(
        database: some DatabaseWriter,
        table: String = DatabaseStore.defaultTable,
        byteBound: Int = DatabaseStore.defaultByteBound
    ) throws(DatabaseStoreError) {
        try self.init(events: DiscoveredEvent.all.map(\.type), database: database, table: table, byteBound: byteBound)
    }

    /// The table the store keeps its records in.
    public var table: String {
        log.table
    }

    /// A report of each drop, in the order they happen, from recovery onwards.
    ///
    /// Reports wait, without a bound, until they are read, so none is missed by reading late.
    /// The sequence ends once the store is gone and every report has been read.
    ///
    /// One task reads the reports at a time. The first iterator to read holds them until its
    /// iteration ends or it is released; a second reader meanwhile waits its turn, logging a
    /// warning once, then reads on from the next report, so the first gets every report in order.
    /// A reader cancelled while it waits returns `nil`.
    public var dropReports: AsyncQueue<DropReport> {
        log.dropReports
    }

    /// The bytes of encoded records the table holds.
    public var byteCount: Int {
        log.byteCount
    }

    /// How many records the table keeps that are not yet delivered.
    public var pendingRecordCount: Int {
        log.pendingRecordCount
    }

    /// Inserts `record` into the table before returning, when its event type is one of `events`
    /// and it fits the bound.
    ///
    /// - Parameter record: The record just tracked.
    /// - Returns: `record` tagged with its row, or as it was when it is kept in memory only.
    public func append(_ record: EventRecord) -> EventRecord {
        log.append(record)
    }

    /// The records earlier runs left in the table, oldest first, with `isRedelivered` set on each
    /// one a delivery had started on; later calls return none.
    public func takeRecoveredRecords() -> [EventRecord] {
        log.takeRecoveredRecords()
    }

    /// Checkpoints the database when it is in WAL mode, which flushes its log to storage, so the
    /// records committed so far survive power loss, not only the app ending, then truncates the
    /// log, so the bytes of rows deleted before the call are gone from it.
    ///
    /// It writes the log into the main file, syncs the main file to storage and shrinks the log,
    /// so call it as the app moves to the background or terminates, not after every write.
    ///
    /// When another connection keeps the log in use, the checkpoint copies what it can, logs a
    /// notice and leaves the rest to a later call; it waits for that connection only as long as
    /// the database's busy mode lets it, holding the database's writer meanwhile. Inside a
    /// transaction it checkpoints nothing and logs a notice. With a rollback journal it does
    /// nothing.
    public func synchronize() {
        log.synchronize()
    }
}
#endif
