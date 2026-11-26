#if canImport(GRDB)
public import Events
public import GRDB
public import Persistence

/// A `RecordStore` that keeps records in a table of the app's own GRDB database, bounded in size,
/// until they are delivered.
///
/// ```swift
/// let database = try DatabasePool(path: databasePath)
/// let store = try DatabaseStore(events: [SignedUp.self, CheckedOut.self], database: database)
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
/// - **What is kept.** Only events of the types in `events`, which conform to `BinaryCodable`,
///   in the same encoding as `SegmentStore`'s. Events of any other type are kept in memory only:
///   they are delivered in this run like any other, are never written, and are lost if the app
///   ends first. The first record of each such type is reported as
///   `DropReport.notPersisted(event:)`, so a type left out of `events` by mistake shows up. A
///   record's context is not kept: a recovered record is in the top-level `ServiceContext`, as
///   its span ended with the earlier run.
/// - **Deleting.** A record's row is deleted once every destination has received it, so a
///   table whose records are all delivered is empty.
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
    /// - Throws: `DatabaseError` when the table can't be created (the database is read-only, or
    ///   `table` holds a double quote) or read, or the rows recovery drops can't be deleted.
    /// - Precondition: `byteBound` is positive. No two of `events` share an `Event.name`.
    public init(
        events: [any (Event & BinaryCodable).Type],
        database: some DatabaseWriter,
        table: String = DatabaseStore.defaultTable,
        byteBound: Int = DatabaseStore.defaultByteBound
    ) throws(DatabaseError) {
        precondition(byteBound > 0, "A database store's bound must be positive, not \(byteBound)")
        log = try DatabaseLog(writer: database, table: table, registry: EventRegistry(events), byteBound: byteBound)
    }

    /// The table the store keeps its records in.
    public var table: String {
        log.table
    }

    /// A report of each drop, in the order they happen, from recovery onwards.
    ///
    /// Reports wait, without a bound, until they are read, so none is missed by reading late.
    /// The sequence has one consumer, and ends once the store is gone.
    public var dropReports: AsyncStream<DropReport> {
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
    /// records committed so far survive power loss, not only the app ending.
    public func synchronize() {
        log.synchronize()
    }
}
#endif
