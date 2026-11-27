#if canImport(GRDB)
import AsyncQueues
import Destinations
import Events
import Foundation
import GRDB
import GRDBPersistence
import Persistence
import SystemPackage
import Testing
import Trackers

// What only a DatabaseStore does: its table, in the app's own database. The behaviour every store
// shares runs against it in the RecordStore suites.

@Suite("DatabaseStore", .timeLimit(.minutes(1)))
struct DatabaseStoreTests {
    struct Tapped: Event, Equatable {
        var number: Int
    }

    struct Retired: Event {
        var number: Int
    }

    /// `Tapped` with its version raised.
    struct TappedVersion2: Event, Equatable {
        static let name = "Tapped"
        static let schemaVersion = 2
        var number: Int
    }

    @Test("The default bound is 5 MiB, and the default table traffluentRecord")
    func defaults() {
        let expectedBound = 5_242_880
        let expectedTable = "traffluentRecord"

        let actualBound = DatabaseStore.defaultByteBound
        let actualTable = DatabaseStore.defaultTable

        #expect(actualBound == expectedBound)
        #expect(actualTable == expectedTable)
    }

    @Test("A store creates its table in the app's database with a migration of its own, beside the app's tables and migrations")
    func createsTable() throws {
        let database = try DatabaseQueue()
        var appMigrator = DatabaseMigrator()
        appMigrator.registerMigration("createPlayer") { db in
            try db.create(table: "player") { $0.autoIncrementedPrimaryKey("id") }
        }
        try appMigrator.migrate(database)
        let expectedMigrations: Set<String> = ["createPlayer", "Traffluent.DatabaseStore.analytics.v1"]

        let sut = try DatabaseStore(events: [Tapped.self], database: database, table: "analytics")

        let tables = try database.read { db in try ["analytics", "player"].filter { try db.tableExists($0) } }
        let migrations = try database.read { try Set(String.fetchAll($0, sql: "SELECT identifier FROM grdb_migrations")) }
        let columns = try database.read { try $0.columns(in: "analytics").map(\.name) }
        #expect(sut.table == "analytics")
        #expect(tables == ["analytics", "player"])
        #expect(migrations == expectedMigrations)
        #expect(columns == ["position", "timestamp", "payload", "isBeingDelivered"])
        // The app's migrator still sees its own migrations applied, and migrates again cleanly.
        try appMigrator.migrate(database)
        let completed = try database.read(appMigrator.hasCompletedMigrations)
        #expect(completed)
    }

    @Test("Opening a store again on its table migrates nothing twice and recovers what is there")
    func reopened() throws {
        let database = try DatabaseQueue()
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        let first = try DatabaseStore(events: [Tapped.self], database: database)
        _ = first.append(EventRecord(event: Tapped(number: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location))

        let sut = try DatabaseStore(events: [Tapped.self], database: database)

        #expect(sut.takeRecoveredRecords().compactMap { $0.event as? Tapped } == [Tapped(number: 1)])
        let migrationCount = try database.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM grdb_migrations") }
        #expect(migrationCount == 1)
    }

    @Test("Two stores on two tables of one database keep their records apart")
    func twoTables() throws {
        let database = try DatabaseQueue()
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        let first = try DatabaseStore(events: [Tapped.self], database: database, table: "first")
        let second = try DatabaseStore(events: [Tapped.self], database: database, table: "second")
        _ = first.append(EventRecord(event: Tapped(number: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location))
        let tag = try #require(second.append(EventRecord(event: Tapped(number: 2), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location)).deliveryTag)

        tag.acknowledger.acknowledge([tag.position])

        let actualFirst = try DatabaseStore(events: [Tapped.self], database: database, table: "first").takeRecoveredRecords()
        let actualSecond = try DatabaseStore(events: [Tapped.self], database: database, table: "second").takeRecoveredRecords()
        #expect(actualFirst.compactMap { $0.event as? Tapped } == [Tapped(number: 1)])
        #expect(actualSecond.isEmpty)
    }

    @Test("A table name that needs quoting, a keyword with a space, works")
    func quotedTable() throws {
        let database = try DatabaseQueue()
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        let sut = try DatabaseStore(events: [Tapped.self], database: database, table: "order records")

        let actual = sut.append(EventRecord(event: Tapped(number: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location))

        let tag = try #require(actual.deliveryTag)
        #expect(tag.acknowledger.willDeliver([tag.position]).isEmpty)
        tag.acknowledger.acknowledge([tag.position])
        #expect(sut.pendingRecordCount == 0)
    }

    @Test("A table name holding a double quote throws the database's DatabaseError: GRDB doesn't escape it in the migration")
    func doubleQuoteInTable() throws {
        let database = try DatabaseQueue()

        let actual = #expect(throws: DatabaseStoreError.self) {
            _ = try DatabaseStore(events: [Tapped.self], database: database, table: "analytics \"records\"")
        }

        guard case .database = actual else {
            Issue.record("Expected the database's error, not \(String(describing: actual))")
            return
        }
    }

    @Test("A row holds the record's timestamp and the same bytes a segment store writes for it")
    func sharedEncoding() throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("DatabaseStoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let database = try DatabaseQueue()
        let timestamp = Date(timeIntervalSinceReferenceDate: 1_234.5)
        let record = EventRecord(event: Tapped(number: 7), timestamp: timestamp, sourceLocation: Events.SourceLocation(file: "/src/A.swift", fileID: "App/A.swift", function: "f()", line: 3, column: 9))
        let segments = try SegmentStore(events: [Tapped.self], directory: directory)
        _ = segments.append(record)
        let name = try #require(try FileManager.default.contentsOfDirectory(atPath: directory.string).first)
        let segment = try #require(FileManager.default.contents(atPath: directory.appending(name).string)).map { $0 }
        // After the segment's header, the frame's length and checksum, and its kind byte.
        let expected = Array(segment[17...])
        let sut = try DatabaseStore(events: [Tapped.self], database: database)

        _ = sut.append(record)

        let row = try #require(try database.read { try Row.fetchOne($0, sql: "SELECT timestamp, payload, isBeingDelivered FROM traffluentRecord") })
        let actualTimestamp: Double = row[0]
        let actualPayload: Data = row[1]
        let actualMarked: Bool = row[2]
        #expect(actualTimestamp == timestamp.timeIntervalSinceReferenceDate)
        #expect(Array(actualPayload) == expected)
        #expect(!actualMarked)
        #expect(sut.byteCount == expected.count)
    }

    @Test("A record exactly the size of the bound is kept")
    func largestRecord() throws {
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        let record = EventRecord(event: Tapped(number: 0), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location)
        let probe = try DatabaseStore(events: [Tapped.self], database: try DatabaseQueue())
        _ = probe.append(record)
        let bound = probe.byteCount
        let sut = try DatabaseStore(events: [Tapped.self], database: try DatabaseQueue(), byteBound: bound)

        let actual = sut.append(record)

        #expect(actual.deliveryTag != nil)
        #expect(sut.byteCount == bound)
    }

    @Test("One record that needs the room of several older ones drops them all, in one report over their timestamps")
    func dropsSeveral() async throws {
        let small = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        let large = Events.SourceLocation(file: "A", fileID: "A", function: String(repeating: "f", count: 400), line: 1, column: 1)
        let probe = try DatabaseStore(events: [Tapped.self], database: try DatabaseQueue())
        _ = probe.append(EventRecord(event: Tapped(number: 0), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: large))
        let database = try DatabaseQueue()
        let sut = try DatabaseStore(events: [Tapped.self], database: database, byteBound: probe.byteCount)
        var reports = sut.dropReports.makeAsyncIterator()
        let expected = DropReport.sizeBound(recordCount: 3, timestamps: Date(timeIntervalSince1970: 10)...Date(timeIntervalSince1970: 30))
        for seconds in [30.0, 10, 20] {
            _ = sut.append(EventRecord(event: Tapped(number: 1), timestamp: Date(timeIntervalSince1970: seconds), sourceLocation: small))
        }

        let actual = sut.append(EventRecord(event: Tapped(number: 2), timestamp: Date(timeIntervalSince1970: 40), sourceLocation: large))

        #expect(actual.deliveryTag != nil)
        #expect(await reports.next() == expected)
        #expect(sut.pendingRecordCount == 1)
        #expect(sut.byteCount == probe.byteCount)
        let rowCount = try await database.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM traffluentRecord") }
        #expect(rowCount == 1)
    }

    @Test("The store's byte count is the sum of its rows' payloads, after appends, drops and acknowledgements")
    func byteCountMatchesTable() throws {
        let database = try DatabaseQueue()
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        let sut = try DatabaseStore(events: [Tapped.self], database: database, byteBound: 300)
        let tags = try (0..<10).map { number in
            try #require(sut.append(EventRecord(event: Tapped(number: number), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location)).deliveryTag)
        }

        tags[9].acknowledger.acknowledge([tags[8].position, tags[9].position])

        let expected = try database.read { try Int.fetchOne($0, sql: "SELECT total(length(payload)) FROM traffluentRecord") }
        let expectedCount = try database.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM traffluentRecord") }
        #expect(sut.byteCount == expected)
        #expect(sut.pendingRecordCount == expectedCount)
        #expect(sut.byteCount <= 300)
    }

    @Test("Undecodable rows are deleted at recovery, so a later store that knows their type gets none")
    func undecodableDeleted() throws {
        let database = try DatabaseQueue()
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        let earlier = try DatabaseStore(events: [Tapped.self, Retired.self], database: database)
        _ = earlier.append(EventRecord(event: Retired(number: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location))
        _ = earlier.append(EventRecord(event: Tapped(number: 2), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location))
        _ = try DatabaseStore(events: [Tapped.self], database: database)

        let sut = try DatabaseStore(events: [Tapped.self, Retired.self], database: database)

        #expect(sut.takeRecoveredRecords().compactMap { $0.event as? Tapped } == [Tapped(number: 2)])
        #expect(sut.pendingRecordCount == 1)
    }

    @Test("Rows stored at another version are deleted at recovery, so a later store at that version gets none")
    func versionMismatchDeleted() throws {
        let database = try DatabaseQueue()
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        let earlier = try DatabaseStore(events: [Tapped.self], database: database)
        _ = earlier.append(EventRecord(event: Tapped(number: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location))
        _ = try DatabaseStore(events: [TappedVersion2.self], database: database)

        let sut = try DatabaseStore(events: [Tapped.self], database: database)

        #expect(sut.takeRecoveredRecords().isEmpty)
        #expect(sut.pendingRecordCount == 0)
    }

    @Test("Rows dropped at recovery, undecodable or stored at another version, are reported on the first open only; the row left is recovered on both")
    func droppedRowsReportedOnce() async throws {
        let database = try DatabaseQueue()
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        do {
            let earlier = try DatabaseStore(events: [Tapped.self, Retired.self], database: database)
            _ = earlier.append(EventRecord(event: Retired(number: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location))
            _ = earlier.append(EventRecord(event: Tapped(number: 2), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location))
        }
        let expectedFirstReports: [DropReport] = [
            .undecodable(recordCount: 1),
            .versionMismatch(event: "Tapped", storedVersion: 1, currentVersion: 2, recordCount: 1),
        ]
        let expectedSecondReports: [DropReport] = []
        let expectedNumbers = [3]

        var firstReports: AsyncQueue<DropReport>.AsyncIterator
        do {
            let first = try DatabaseStore(events: [TappedVersion2.self], database: database)
            firstReports = first.dropReports.makeAsyncIterator()
            _ = first.append(EventRecord(event: TappedVersion2(number: 3), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location))
        }
        var actualFirstReports: [DropReport] = []
        while let report = await firstReports.next() { actualFirstReports.append(report) }
        var secondReports: AsyncQueue<DropReport>.AsyncIterator
        let actualNumbers: [Int]
        do {
            let sut = try DatabaseStore(events: [TappedVersion2.self], database: database)
            secondReports = sut.dropReports.makeAsyncIterator()
            actualNumbers = sut.takeRecoveredRecords().compactMap { ($0.event as? TappedVersion2)?.number }
        }
        var actualSecondReports: [DropReport] = []
        while let report = await secondReports.next() { actualSecondReports.append(report) }

        #expect(actualFirstReports == expectedFirstReports)
        #expect(actualSecondReports == expectedSecondReports)
        #expect(actualNumbers == expectedNumbers)
    }

    @Test("Tracking inside one of the app's own writes neither waits for the write nor joins it: the worker commits the record after it")
    func trackInsideAppWrite() async throws {
        let database = try DatabaseQueue()
        try await database.write { try $0.create(table: "player") { $0.autoIncrementedPrimaryKey("id") } }
        let store = try DatabaseStore(events: [Tapped.self], database: database)
        let tracker = Tracker(store: store)

        let pendingInsideWrite = try await database.write { db in
            try db.execute(sql: "INSERT INTO player DEFAULT VALUES")
            tracker.track(Tapped(number: 1))
            return try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM traffluentRecord")
        }
        await tracker.flush()

        #expect(pendingInsideWrite == 0)
        #expect(store.pendingRecordCount == 1)
        let next = try DatabaseStore(events: [Tapped.self], database: database)
        #expect(next.takeRecoveredRecords().compactMap { $0.event as? Tapped } == [Tapped(number: 1)])
    }

    @Test("A record tracked inside one of the app's writes that rolls back is still written, outside the app's transaction")
    func trackInsideRolledBackWrite() async throws {
        struct Abandoned: Error {}
        let database = try DatabaseQueue()
        let store = try DatabaseStore(events: [Tapped.self], database: database)
        let tracker = Tracker(store: store)

        try? await database.write { _ in
            tracker.track(Tapped(number: 1))
            throw Abandoned()
        }
        await tracker.flush()

        let rowCount = try await database.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM traffluentRecord") }
        #expect(rowCount == 1)
    }

    @Test("An acknowledgement that can't be written leaves the rows, and the next launch delivers them marked redelivered")
    func acknowledgementFails() throws {
        let database = try DatabaseQueue()
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        let sut = try DatabaseStore(events: [Tapped.self], database: database)
        let tag = try #require(sut.append(EventRecord(event: Tapped(number: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location)).deliveryTag)
        _ = tag.acknowledger.willDeliver([tag.position])
        try database.writeWithoutTransaction { try $0.execute(sql: "PRAGMA query_only = 1") }

        tag.acknowledger.acknowledge([tag.position])

        #expect(sut.pendingRecordCount == 1)
        try database.writeWithoutTransaction { try $0.execute(sql: "PRAGMA query_only = 0") }
        let next = try DatabaseStore(events: [Tapped.self], database: database)
        #expect(next.takeRecoveredRecords().map(\.isRedelivered) == [true])
    }

    @Test("A store on a database it can't write throws the database's DatabaseError")
    func readOnlyDatabase() throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("DatabaseStoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        try FileManager.default.createDirectory(atPath: directory.string, withIntermediateDirectories: true)
        let path = directory.appending("app.sqlite").string
        try DatabaseQueue(path: path).write { try $0.create(table: "player") { $0.autoIncrementedPrimaryKey("id") } }
        var configuration = Configuration()
        configuration.readonly = true
        let database = try DatabaseQueue(path: path, configuration: configuration)

        let actual = #expect(throws: DatabaseStoreError.self) {
            _ = try DatabaseStore(events: [Tapped.self], database: database)
        }

        guard case .database = actual else {
            Issue.record("Expected the database's error, not \(String(describing: actual))")
            return
        }
    }

    @Test("Synchronizing a WAL database checkpoints it, so its main file alone holds the records")
    func synchronizeCheckpoints() throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("DatabaseStoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        try FileManager.default.createDirectory(atPath: directory.string, withIntermediateDirectories: true)
        let path = directory.appending("app.sqlite").string
        let copy = directory.appending("copy.sqlite").string
        let database = try DatabasePool(path: path)
        let sut = try DatabaseStore(events: [Tapped.self], database: database)
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        _ = sut.append(EventRecord(event: Tapped(number: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location))

        sut.synchronize()

        // Only the main file, without its write-ahead log.
        try FileManager.default.copyItem(atPath: path, toPath: copy)
        let next = try DatabaseStore(events: [Tapped.self], database: try DatabaseQueue(path: copy))
        #expect(next.takeRecoveredRecords().compactMap { $0.event as? Tapped } == [Tapped(number: 1)])
    }
}

extension DatabaseStoreTests.Tapped: Codable {}

extension DatabaseStoreTests.TappedVersion2: Codable {}

extension DatabaseStoreTests.Retired: Codable {}
#endif
