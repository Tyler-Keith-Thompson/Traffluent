#if canImport(GRDB)
import Events
import Foundation
import GRDB
import Logging
import Persistence
import Synchronization

/// The table of a ``DatabaseStore``, and what is known about it.
///
/// Each record is a row: its position (an autoincremented primary key, never reused, so a stale
/// acknowledgement can't delete a newer row), its timestamp, its bytes in the shared record
/// encoding, and whether a delivery has started on it.
final class DatabaseLog: Acknowledger {
    struct State {
        /// The payload bytes of every row.
        var byteCount: Int
        /// How many rows there are: every row is a record not yet delivered.
        var pendingCount: Int
        /// The records recovered from earlier runs, tagged, until they are taken.
        var recovered: [EventRecord]
    }

    /// The oldest rows deleted to make room, for a drop report.
    struct Eviction {
        var recordCount = 0
        var byteCount = 0
        var timestamps: ClosedRange<Date>?
        var lastPosition: Int64?

        /// Counts the row at `position`, tracked at `timestamp`, holding `byteCount` bytes.
        mutating func add(position: Int64, timestamp: Date, byteCount rowByteCount: Int) {
            recordCount += 1
            byteCount += rowByteCount
            timestamps = timestamps.map { min($0.lowerBound, timestamp)...max($0.upperBound, timestamp) } ?? timestamp...timestamp
            lastPosition = position
        }

        /// The report of the rows deleted, or `nil` when none was.
        var report: DropReport? {
            timestamps.map { .sizeBound(recordCount: recordCount, timestamps: $0) }
        }
    }

    let writer: any DatabaseWriter
    let table: String
    private let registry: EventRegistry
    private let byteBound: Int
    // A Mutex rather than an actor: `append` is synchronous, as `RecordStore` declares it, so it
    // can't await an actor. The state changes only inside a write to the database, once it
    // commits, so the lock is always taken inside GRDB's writer and never held while waiting for
    // it: the tracker's worker appending while the app writes can't deadlock with a delivery.
    private let state: Mutex<State>
    let dropReports: AsyncStream<DropReport>
    private let dropReporter: AsyncStream<DropReport>.Continuation
    private let unlistedTypes = UnlistedEventTypes()

    private static let logger = Logger(label: "GRDBPersistence.DatabaseStore")

    /// The identifier, in `grdb_migrations`, of the migration that creates `table`.
    static func migrationIdentifier(of table: String) -> String {
        "Traffluent.DatabaseStore.\(table).v1"
    }

    /// The log in `table` of `writer`, created if missing, and recovered from the rows there.
    init(writer: some DatabaseWriter, table: String, registry: EventRegistry, byteBound: Int) throws(DatabaseError) {
        self.writer = writer
        self.table = table
        self.registry = registry
        self.byteBound = byteBound
        (dropReports, dropReporter) = AsyncStream.makeStream(of: DropReport.self)
        var migrator = DatabaseMigrator()
        migrator.registerMigration(Self.migrationIdentifier(of: table)) { db in
            try db.create(table: table) { definition in
                definition.autoIncrementedPrimaryKey("position")
                definition.column("timestamp", .double).notNull()
                definition.column("payload", .blob).notNull()
                definition.column("isBeingDelivered", .boolean).notNull().defaults(to: false)
            }
        }
        var reports: [DropReport] = []
        let recovered: Recovery
        do {
            try migrator.migrate(writer)
            recovered = try writer.write { db in
                try Self.recover(from: db, table: table, registry: registry, byteBound: byteBound, reports: &reports)
            }
        } catch let error as DatabaseError {
            throw error
        } catch {
            // GRDB's accesses throw DatabaseError; anything else came from a migration's body,
            // which is this file's own.
            throw DatabaseError(message: String(describing: error))
        }
        state = Mutex(State(byteCount: recovered.byteCount, pendingCount: recovered.records.count, recovered: []))
        let tagged = recovered.records.map { recovered in
            var record = recovered.record
            record.deliveryTag = DeliveryTag(acknowledger: self, position: UInt64(recovered.position))
            return record
        }
        state.withLock { $0.recovered = tagged }
        for report in reports {
            dropReporter.yield(report)
        }
    }

    deinit {
        dropReporter.finish()
    }

    // MARK: Appending

    /// Inserts `record`, or returns it as it was when its event type isn't persisted, it can't
    /// fit in the bound, or the insert fails; a failed insert is reported.
    func append(_ record: EventRecord) -> EventRecord {
        guard let registration = registry.registration(of: type(of: record.event)) else {
            if unlistedTypes.insert(type(of: record.event)) {
                Self.logger.notice("Kept \(record.name) records in memory only: its type isn't one of the store's events")
                dropReporter.yield(.notPersisted(event: record.name))
            }
            return record
        }
        let payload = RecordEncoding.bytes(of: record, registration: registration)
        guard payload.count <= byteBound else {
            Self.logger.notice("Kept a \(registration.name) record in memory only: its \(payload.count) bytes are more than a table bounded to \(byteBound) bytes can hold")
            return record
        }
        let position: Int64
        let eviction: Eviction
        do {
            (position, eviction) = try writer.unsafeReentrantWrite { db in
                // Reentrant, so an append made directly inside one of the app's own writes joins
                // its transaction rather than trapping; a savepoint, so the deletions and the insert commit together
                // or not at all, inside a transaction or out of one.
                var position: Int64 = 0
                var eviction = Eviction()
                try db.inSavepoint {
                    let excess = state.withLock { $0.byteCount } + payload.count - byteBound
                    if excess > 0 {
                        eviction = try oldestRows(holding: excess, in: db)
                        if let last = eviction.lastPosition {
                            try db.execute(sql: "DELETE FROM \(table.quotedDatabaseIdentifier) WHERE position <= ?", arguments: [last])
                        }
                    }
                    try db.cachedStatement(sql: "INSERT INTO \(table.quotedDatabaseIdentifier) (timestamp, payload) VALUES (?, ?)")
                        .execute(arguments: [record.timestamp.timeIntervalSinceReferenceDate, Data(payload)])
                    position = db.lastInsertedRowID
                    return .commit
                }
                state.withLock { state in
                    state.byteCount += payload.count - eviction.byteCount
                    state.pendingCount += 1 - eviction.recordCount
                }
                return (position, eviction)
            }
        } catch {
            Self.logger.error("Kept a \(registration.name) record in memory only: inserting it into \(table) failed with \(error)")
            dropReporter.yield(.writeFailed(recordCount: 1, timestamps: record.timestamp...record.timestamp))
            return record
        }
        if let report = eviction.report {
            dropReporter.yield(report)
        }
        var tagged = record
        tagged.deliveryTag = DeliveryTag(acknowledger: self, position: UInt64(position))
        return tagged
    }

    /// The oldest rows whose payloads hold at least `byteCount` bytes, or every row when they
    /// hold fewer.
    ///
    /// In a function of its own so the cursor is gone before the caller deletes the rows.
    private func oldestRows(holding byteCount: Int, in db: Database) throws -> Eviction {
        var eviction = Eviction()
        let rows = try Row.fetchCursor(db, sql: "SELECT position, timestamp, length(payload) FROM \(table.quotedDatabaseIdentifier) ORDER BY position")
        while eviction.byteCount < byteCount, let row = try rows.next() {
            eviction.add(position: row[0], timestamp: Date(timeIntervalSinceReferenceDate: row[1]), byteCount: row[2])
        }
        return eviction
    }

    // MARK: Delivery

    /// Marks the rows at `positions` as being delivered, in one transaction, returning them all
    /// when the mark can't be written.
    ///
    /// A record whose mark failed is withheld from this delivery rather than delivered unmarked:
    /// after a crash it would come back without `isRedelivered`, sent twice unannounced. Its row
    /// stays, and it is delivered on a later launch.
    func willDeliver(_ positions: [UInt64]) -> Set<UInt64> {
        do {
            try writer.unsafeReentrantWrite { db in
                try db.inSavepoint {
                    let statement = try db.cachedStatement(sql: "UPDATE \(table.quotedDatabaseIdentifier) SET isBeingDelivered = 1 WHERE position = ?")
                    for position in positions {
                        try statement.execute(arguments: [Int64(truncatingIfNeeded: position)])
                    }
                    return .commit
                }
            }
            return []
        } catch {
            Self.logger.error("Held \(positions.count) records in \(table) back from delivery until a later launch: marking them as being delivered failed with \(error)")
            return Set(positions)
        }
    }

    /// Deletes the rows at `positions`; positions with no row are skipped.
    func acknowledge(_ positions: [UInt64]) {
        do {
            try writer.unsafeReentrantWrite { db in
                var deleted = (recordCount: 0, byteCount: 0)
                try db.inSavepoint {
                    let statement = try db.cachedStatement(sql: "DELETE FROM \(table.quotedDatabaseIdentifier) WHERE position = ? RETURNING length(payload)")
                    for position in positions {
                        guard let byteCount = try Int.fetchOne(statement, arguments: [Int64(truncatingIfNeeded: position)]) else { continue }
                        deleted.recordCount += 1
                        deleted.byteCount += byteCount
                    }
                    return .commit
                }
                state.withLock { state in
                    state.byteCount -= deleted.byteCount
                    state.pendingCount -= deleted.recordCount
                }
            }
        } catch {
            // The rows stay, marked as being delivered: a later launch delivers them again, with
            // isRedelivered set.
            Self.logger.error("Couldn't delete \(positions.count) delivered records from \(table): \(error)")
        }
    }

    /// The records at `positions` whose rows are still in the table, read back in one read.
    ///
    /// A record whose row was deleted (delivered, or dropped by the bound, which reported it) has
    /// none, and neither does any when the read fails, which is logged.
    func records(at positions: [UInt64]) -> [EventRecord] {
        do {
            // Reentrant, as the writes are, so a read made inside one of the app's own accesses
            // doesn't trap.
            return try writer.unsafeReentrantRead { db in
                let statement = try db.cachedStatement(sql: "SELECT payload FROM \(table.quotedDatabaseIdentifier) WHERE position = ?")
                var records: [EventRecord] = []
                for position in positions {
                    guard let payload = try Data.fetchOne(statement, arguments: [Int64(truncatingIfNeeded: position)]) else { continue }
                    let reading: RecordEncoding.Reading
                    do throws(BinaryDecodingError) {
                        reading = try RecordEncoding.record(from: Array(payload)[...], registry: registry)
                    } catch {
                        Self.logger.error("Couldn't read a record in \(table) back, so it waits for a later launch: decoding it failed with \(error)")
                        continue
                    }
                    guard case .record(var record) = reading else {
                        Self.logger.notice("Read a record in \(table) back at another version of its event than this release's, so it waits for a later launch")
                        continue
                    }
                    record.deliveryTag = DeliveryTag(acknowledger: self, position: position)
                    records.append(record)
                }
                return records
            }
        } catch {
            Self.logger.error("Couldn't read \(positions.count) records in \(table) back for a destination whose buffer dropped them, so they wait for a later launch: \(error)")
            return []
        }
    }

    // MARK: Synchronizing

    /// Checkpoints the database, which in WAL mode flushes its log to storage first.
    func synchronize() {
        do {
            try writer.unsafeReentrantWrite { db in
                _ = try db.checkpoint(.passive)
            }
        } catch {
            Self.logger.error("Couldn't checkpoint the database holding \(table): \(error)")
        }
    }

    // MARK: Reading

    /// The records recovered from earlier runs, tagged; later calls return none.
    func takeRecoveredRecords() -> [EventRecord] {
        state.withLock { state in
            let recovered = state.recovered
            state.recovered = []
            return recovered
        }
    }

    /// The payload bytes the table holds.
    var byteCount: Int {
        state.withLock { $0.byteCount }
    }

    /// The records kept that are not yet acknowledged.
    var pendingRecordCount: Int {
        state.withLock { $0.pendingCount }
    }

    // MARK: Recovering

    /// A record recovered from an earlier run, and its row.
    struct Recovered {
        let record: EventRecord
        let position: Int64
        let byteCount: Int
    }

    /// What recovery found: the records kept, oldest first, and their payload bytes.
    struct Recovery {
        var records: [Recovered]
        var byteCount: Int
    }

    /// The rows of `table`, decoded; rows that can't be decoded are deleted, and then the oldest
    /// rows while the table holds more than `byteBound` bytes.
    private static func recover(
        from db: Database,
        table: String,
        registry: EventRegistry,
        byteBound: Int,
        reports: inout [DropReport]
    ) throws -> Recovery {
        var recovery = Recovery(records: [], byteCount: 0)
        var undecodable: [Int64] = []
        var mismatched: [Int64] = []
        var mismatches = VersionMismatchCounts()
        let rows = try Row.fetchAll(db, sql: "SELECT position, payload, isBeingDelivered FROM \(table.quotedDatabaseIdentifier) ORDER BY position")
        for row in rows {
            let position: Int64 = row[0]
            let payload: Data = row[1]
            do throws(BinaryDecodingError) {
                switch try RecordEncoding.record(from: Array(payload)[...], registry: registry) {
                case .record(var record):
                    record.isRedelivered = row[2]
                    recovery.records.append(Recovered(record: record, position: position, byteCount: payload.count))
                    recovery.byteCount += payload.count
                case .versionMismatch(let event, let storedVersion, let currentVersion):
                    mismatched.append(position)
                    mismatches.add(event: event, storedVersion: storedVersion, currentVersion: currentVersion)
                }
            } catch {
                undecodable.append(position)
            }
        }
        if !undecodable.isEmpty || !mismatched.isEmpty {
            let statement = try db.makeStatement(sql: "DELETE FROM \(table.quotedDatabaseIdentifier) WHERE position = ?")
            for position in undecodable + mismatched {
                try statement.execute(arguments: [position])
            }
        }
        if !undecodable.isEmpty {
            reports.append(.undecodable(recordCount: undecodable.count))
        }
        reports += mismatches.reports
        var eviction = Eviction()
        while recovery.byteCount > byteBound, !recovery.records.isEmpty {
            let oldest = recovery.records.removeFirst()
            eviction.add(position: oldest.position, timestamp: oldest.record.timestamp, byteCount: oldest.byteCount)
            recovery.byteCount -= oldest.byteCount
        }
        if let last = eviction.lastPosition, let report = eviction.report {
            try db.execute(sql: "DELETE FROM \(table.quotedDatabaseIdentifier) WHERE position <= ?", arguments: [last])
            reports.append(report)
        }
        return recovery
    }
}
#endif
