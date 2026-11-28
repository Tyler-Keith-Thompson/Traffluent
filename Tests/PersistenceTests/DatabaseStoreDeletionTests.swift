#if canImport(GRDB)
import Destinations
import Events
import Foundation
import GRDB
import GRDBPersistence
import Persistence
import SystemPackage
import Testing
import Trackers

// What a DatabaseStore leaves on disk once a record is delivered (TRAF-146): its deletes zero
// what they free, and synchronize() empties a WAL database's log. Each test scans the raw bytes of
// every file in the database's directory, as RecordStoreContextTests' vendorIdentifierNeverWritten
// does, for a short Sensitive value that fits in a page, a long one that spills onto overflow
// pages, and the session in each form it could take.

@Suite("DatabaseStore: deleted records", .timeLimit(.minutes(1)))
struct DatabaseStoreDeletionTests {
    struct SignedUp: Event {
        var email: Sensitive<String>
        var note: Sensitive<String>
    }

    struct Retired: Event {
        var note: Sensitive<String>
    }

    /// The journal mode a test's database runs in.
    enum Journal: String, CaseIterable, CustomTestStringConvertible {
        /// A `DatabaseQueue`: a rollback journal.
        case rollback
        /// A `DatabasePool`: WAL.
        case wal

        var testDescription: String {
            rawValue
        }
    }

    @Test("In a WAL database, synchronize() after delivery leaves no byte of a delivered record's Sensitive values or session in the main file or the -wal; before delivery they are there")
    func walHoldsNothingDelivered() async throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("DatabaseStoreDeletionTests-\(UUID().uuidString)").string
        defer { try? FileManager.default.removeItem(atPath: directory) }
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let session = try #require(UUID(uuidString: "019A2B3C-4D5E-7F60-8172-93A4B5C6D7E8"))
        let email = "ada.lovelace@example.com"
        let marker = "TRAF146-overflowing-note;"
        let markers = [
            Array(email.utf8),
            Array(marker.utf8),
            Array(session.uuidString.utf8),
            Array(session.uuidString.lowercased().utf8),
            withUnsafeBytes(of: session.uuid) { Array($0) },
        ]
        // The forms the store writes: the session as Foundation's Codable writes a UUID.
        let written = Array(markers.prefix(3))
        func files() throws -> [String: [UInt8]] {
            let names = try FileManager.default.contentsOfDirectory(atPath: directory)
            return names.reduce(into: [:]) { files, name in
                files[name] = FileManager.default.contents(atPath: directory + "/" + name).map(Array.init)
            }
        }
        func markersFound(in files: [String: [UInt8]]) -> [[UInt8]] {
            markers.filter { marker in files.values.contains { $0.firstRange(of: marker) != nil } }
        }
        let database = try DatabasePool(path: directory + "/records.sqlite")
        let store = try DatabaseStore(events: [SignedUp.self], database: database)
        let tracker = Tracker(store: store, enrichers: [Enricher { $0[SessionKey.self] = session }])
        for _ in 0 ..< 10 {
            tracker.track(SignedUp(email: Sensitive(email), note: Sensitive(String(repeating: marker, count: 300))))
        }
        await tracker.finish()
        // In the log alone: nothing has checkpointed it yet.
        let foundInLogBeforeDelivery = markersFound(in: try files().filter { $0.key == "records.sqlite-wal" })
        let destination = InMemoryDestination()
        let expectedLog: [UInt8] = []

        try await tracker.records.batch(strategy: .count(10)).deliver(to: destination).execute()
        store.synchronize()

        let actual = try files()
        #expect(written.allSatisfy(foundInLogBeforeDelivery.contains))
        #expect(destination.records.count == 10)
        #expect(store.pendingRecordCount == 0)
        #expect(actual["records.sqlite-wal"] == expectedLog)
        #expect(markersFound(in: actual).isEmpty)
    }

    @Test("With a rollback journal, delivery leaves no byte of a delivered record's Sensitive values or session in the main file; before delivery they are there")
    func rollbackJournalHoldsNothingDelivered() async throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("DatabaseStoreDeletionTests-\(UUID().uuidString)").string
        defer { try? FileManager.default.removeItem(atPath: directory) }
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let path = directory + "/records.sqlite"
        let session = try #require(UUID(uuidString: "019A2B3C-4D5E-7F60-8172-93A4B5C6D7E8"))
        let email = "ada.lovelace@example.com"
        let marker = "TRAF146-overflowing-note;"
        let markers = [
            Array(email.utf8),
            Array(marker.utf8),
            Array(session.uuidString.utf8),
            Array(session.uuidString.lowercased().utf8),
            withUnsafeBytes(of: session.uuid) { Array($0) },
        ]
        // The forms the store writes: the session as Foundation's Codable writes a UUID.
        let written = Array(markers.prefix(3))
        func markersFound(in file: [UInt8]) -> [[UInt8]] {
            markers.filter { file.firstRange(of: $0) != nil }
        }
        let database = try DatabaseQueue(path: path)
        let store = try DatabaseStore(events: [SignedUp.self], database: database)
        let tracker = Tracker(store: store, enrichers: [Enricher { $0[SessionKey.self] = session }])
        for _ in 0 ..< 10 {
            tracker.track(SignedUp(email: Sensitive(email), note: Sensitive(String(repeating: marker, count: 300))))
        }
        await tracker.finish()
        let beforeDelivery = try #require(FileManager.default.contents(atPath: path).map(Array.init))
        let destination = InMemoryDestination()
        let expectedNames = ["records.sqlite"]

        try await tracker.records.batch(strategy: .count(10)).deliver(to: destination).execute()
        store.synchronize()

        let actual = try #require(FileManager.default.contents(atPath: path).map(Array.init))
        let directoryNames = try FileManager.default.contentsOfDirectory(atPath: directory)
        #expect(written.allSatisfy(markersFound(in: beforeDelivery).contains))
        #expect(destination.records.count == 10)
        #expect(directoryNames == expectedNames)
        #expect(markersFound(in: actual).isEmpty)
    }

    @Test("A store's deletes zero what they free even when the app turned secure_delete off, and leave the app's setting as it was", arguments: Journal.allCases)
    func zeroesWithSecureDeleteOff(journal: Journal) async throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("DatabaseStoreDeletionTests-\(UUID().uuidString)").string
        defer { try? FileManager.default.removeItem(atPath: directory) }
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let session = try #require(UUID(uuidString: "019A2B3C-4D5E-7F60-8172-93A4B5C6D7E8"))
        let email = "ada.lovelace@example.com"
        let marker = "TRAF146-overflowing-note;"
        let markers = [
            Array(email.utf8),
            Array(marker.utf8),
            Array(session.uuidString.utf8),
            Array(session.uuidString.lowercased().utf8),
            withUnsafeBytes(of: session.uuid) { Array($0) },
        ]
        // The forms the store writes: the session as Foundation's Codable writes a UUID.
        let written = Array(markers.prefix(3))
        func markersFound() throws -> [[UInt8]] {
            let files = try FileManager.default.contentsOfDirectory(atPath: directory).compactMap { name in
                FileManager.default.contents(atPath: directory + "/" + name).map(Array.init)
            }
            return markers.filter { marker in files.contains { $0.firstRange(of: marker) != nil } }
        }
        let path = directory + "/records.sqlite"
        let database: any DatabaseWriter = journal == .rollback ? try DatabaseQueue(path: path) : try DatabasePool(path: path)
        try await database.writeWithoutTransaction { try $0.execute(sql: "PRAGMA secure_delete = 0") }
        let store = try DatabaseStore(events: [SignedUp.self], database: database)
        let tracker = Tracker(store: store, enrichers: [Enricher { $0[SessionKey.self] = session }])
        for _ in 0 ..< 10 {
            tracker.track(SignedUp(email: Sensitive(email), note: Sensitive(String(repeating: marker, count: 300))))
        }
        await tracker.finish()
        let foundBeforeDelivery = try markersFound()
        let expectedSetting = 0

        try await tracker.records.batch(strategy: .count(10)).deliver(to: InMemoryDestination()).execute()
        store.synchronize()

        let actual = try markersFound()
        let actualSetting = try await database.writeWithoutTransaction { try Int.fetchOne($0, sql: "PRAGMA secure_delete") }
        #expect(written.allSatisfy(foundBeforeDelivery.contains))
        #expect(actual.isEmpty)
        #expect(actualSetting == expectedSetting)
    }

    @Test("Appending, evicting and acknowledging leave the app's secure_delete as the app set it: OFF, ON or FAST", arguments: [("OFF", 0), ("ON", 1), ("FAST", 2)])
    func secureDeleteRestored(setting: String, expected: Int) throws {
        let database = try DatabaseQueue()
        try database.writeWithoutTransaction { try $0.execute(sql: "PRAGMA secure_delete = \(setting)") }
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        // Each record's payload is over 7,500 bytes, so the bound holds one and the second
        // append evicts the first.
        let sut = try DatabaseStore(events: [SignedUp.self], database: database, byteBound: 10_000)
        let first = EventRecord(event: SignedUp(email: Sensitive("first@example.com"), note: Sensitive(String(repeating: "note;", count: 1_500))), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location)
        let second = EventRecord(event: SignedUp(email: Sensitive("second@example.com"), note: Sensitive(String(repeating: "note;", count: 1_500))), timestamp: Date(timeIntervalSince1970: 1), sourceLocation: location)

        _ = sut.append(first)
        let tag = try #require(sut.append(second).deliveryTag)
        _ = tag.acknowledger.willDeliver([tag.position])
        tag.acknowledger.acknowledge([tag.position])
        sut.synchronize()

        let actual = try database.writeWithoutTransaction { try Int.fetchOne($0, sql: "PRAGMA secure_delete") }
        #expect(sut.pendingRecordCount == 0)
        #expect(actual == expected)
    }

    @Test("A store reads the app's secure_delete afresh on each write, so a setting the app changes between appends is the one put back")
    func secureDeleteReadEachTime() throws {
        let database = try DatabaseQueue()
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        let sut = try DatabaseStore(events: [SignedUp.self], database: database, byteBound: 10_000)
        func record(_ number: Int) -> EventRecord {
            EventRecord(event: SignedUp(email: Sensitive("\(number)@example.com"), note: Sensitive(String(repeating: "note;", count: 1_500))), timestamp: Date(timeIntervalSince1970: Double(number)), sourceLocation: location)
        }
        try database.writeWithoutTransaction { try $0.execute(sql: "PRAGMA secure_delete = FAST") }
        _ = sut.append(record(1))
        _ = sut.append(record(2))
        try database.writeWithoutTransaction { try $0.execute(sql: "PRAGMA secure_delete = OFF") }
        let expected = 0

        _ = sut.append(record(3))
        _ = sut.append(record(4))

        let actual = try database.writeWithoutTransaction { try Int.fetchOne($0, sql: "PRAGMA secure_delete") }
        #expect(sut.pendingRecordCount == 1)
        #expect(actual == expected)
    }

    @Test("Small records inserted with secure_delete off leave no byte of the delivered ones behind once they are deleted, though their inserts split pages", arguments: Journal.allCases)
    func smallRecordsInsertedWithSecureDeleteOff(journal: Journal) async throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("DatabaseStoreDeletionTests-\(UUID().uuidString)").string
        defer { try? FileManager.default.removeItem(atPath: directory) }
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let path = directory + "/records.sqlite"
        let database: any DatabaseWriter = journal == .rollback ? try DatabaseQueue(path: path) : try DatabasePool(path: path)
        try await database.writeWithoutTransaction { try $0.execute(sql: "PRAGMA secure_delete = 0") }
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        let sut = try DatabaseStore(events: [SignedUp.self], database: database)
        // Each record about 130 bytes, its marker its own, so a stale copy of any one shows.
        func marker(_ number: Int) -> String {
            "TRAF146-small-\(String(number + 10_000).dropFirst())-marker"
        }
        func markersFound(_ numbers: Range<Int>) throws -> [Int] {
            let files = try FileManager.default.contentsOfDirectory(atPath: directory).compactMap { name in
                FileManager.default.contents(atPath: directory + "/" + name).map(Array.init)
            }
            return numbers.filter { number in files.contains { $0.firstRange(of: Array(marker(number).utf8)) != nil } }
        }
        var tags: [DeliveryTag] = []
        for number in 0 ..< 400 {
            let record = EventRecord(event: SignedUp(email: Sensitive(marker(number)), note: Sensitive("n")), timestamp: Date(timeIntervalSince1970: Double(number)), sourceLocation: location)
            tags.append(try #require(sut.append(record).deliveryTag))
        }
        let delivered = Array(tags.prefix(300))
        let acknowledger = try #require(delivered.first?.acknowledger)
        let expectedKept = Array(300 ..< 400)

        _ = acknowledger.willDeliver(delivered.map(\.position))
        acknowledger.acknowledge(delivered.map(\.position))
        sut.synchronize()

        let actualDelivered = try markersFound(0 ..< 300)
        let actualKept = try markersFound(300 ..< 400)
        #expect(sut.pendingRecordCount == 100)
        #expect(actualDelivered.isEmpty)
        #expect(actualKept == expectedKept)
    }

    @Test("synchronize() called inside one of the app's own writes returns, checkpointing nothing, and a later one outside it empties the log")
    func synchronizeInsideAppWrite() async throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("DatabaseStoreDeletionTests-\(UUID().uuidString)").string
        defer { try? FileManager.default.removeItem(atPath: directory) }
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let database = try DatabasePool(path: directory + "/records.sqlite")
        let sut = try DatabaseStore(events: [SignedUp.self], database: database)
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        let tag = try #require(sut.append(EventRecord(event: SignedUp(email: Sensitive("ada@example.com"), note: Sensitive("n")), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location)).deliveryTag)
        _ = tag.acknowledger.willDeliver([tag.position])
        tag.acknowledger.acknowledge([tag.position])
        let marker = Array("ada@example.com".utf8)
        func logHoldsMarker() -> Bool {
            let bytes = FileManager.default.contents(atPath: directory + "/records.sqlite-wal").map(Array.init) ?? []
            return bytes.firstRange(of: marker) != nil
        }

        try await database.write { _ in sut.synchronize() }
        let afterInside = logHoldsMarker()
        sut.synchronize()

        let actual = logHoldsMarker()
        #expect(afterInside)
        #expect(!actual)
    }

    @Test("While an open read transaction keeps the log in use, synchronize() returns and the -wal keeps the delivered records' bytes; once it ends, the next synchronize() clears them")
    func heldReaderLeavesLogUntilNextSynchronize() async throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("DatabaseStoreDeletionTests-\(UUID().uuidString)").string
        defer { try? FileManager.default.removeItem(atPath: directory) }
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let session = try #require(UUID(uuidString: "019A2B3C-4D5E-7F60-8172-93A4B5C6D7E8"))
        let email = "ada.lovelace@example.com"
        let marker = "TRAF146-overflowing-note;"
        let markers = [
            Array(email.utf8),
            Array(marker.utf8),
            Array(session.uuidString.utf8),
        ]
        func markersFound(inFile name: String) -> [[UInt8]] {
            let bytes = FileManager.default.contents(atPath: directory + "/" + name).map(Array.init) ?? []
            return markers.filter { bytes.firstRange(of: $0) != nil }
        }
        let database = try DatabasePool(path: directory + "/records.sqlite")
        let store = try DatabaseStore(events: [SignedUp.self], database: database)
        let tracker = Tracker(store: store, enrichers: [Enricher { $0[SessionKey.self] = session }])
        for _ in 0 ..< 10 {
            tracker.track(SignedUp(email: Sensitive(email), note: Sensitive(String(repeating: marker, count: 300))))
        }
        await tracker.finish()
        var reader: DatabaseSnapshot? = try database.makeSnapshot()
        try await tracker.records.batch(strategy: .count(10)).deliver(to: InMemoryDestination()).execute()

        store.synchronize()
        let whileReading = markersFound(inFile: "records.sqlite-wal")
        let readerRowCount = try await reader?.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM traffluentRecord") }
        reader = nil
        store.synchronize()

        let actualLog = markersFound(inFile: "records.sqlite-wal")
        let actualMain = markersFound(inFile: "records.sqlite")
        #expect(readerRowCount == 10)
        #expect(whileReading.count == markers.count)
        #expect(store.pendingRecordCount == 0)
        #expect(actualLog.isEmpty)
        #expect(actualMain.isEmpty)
    }

    @Test("A row the bound evicts to make room leaves no byte of its Sensitive values behind, with secure_delete off", arguments: Journal.allCases)
    func evictedRowZeroed(journal: Journal) async throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("DatabaseStoreDeletionTests-\(UUID().uuidString)").string
        defer { try? FileManager.default.removeItem(atPath: directory) }
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let evicted = Array("TRAF146-evicted-note;".utf8)
        let kept = Array("TRAF146-kept-note;".utf8)
        func found(_ marker: [UInt8]) throws -> Bool {
            try FileManager.default.contentsOfDirectory(atPath: directory).contains { name in
                FileManager.default.contents(atPath: directory + "/" + name).map { Array($0).firstRange(of: marker) != nil } ?? false
            }
        }
        let path = directory + "/records.sqlite"
        let database: any DatabaseWriter = journal == .rollback ? try DatabaseQueue(path: path) : try DatabasePool(path: path)
        try await database.writeWithoutTransaction { try $0.execute(sql: "PRAGMA secure_delete = 0") }
        // The first payload is over 7,500 bytes, the second over 3,000 but small enough to fit in a
        // page, so the second evicts the first without writing over the pages the first spilled
        // onto.
        let store = try DatabaseStore(events: [SignedUp.self], database: database, byteBound: 10_000)
        let tracker = Tracker(store: store)
        tracker.track(SignedUp(email: Sensitive("first@example.com"), note: Sensitive(String(repeating: "TRAF146-evicted-note;", count: 360))))
        await tracker.flush()
        store.synchronize()
        let foundBeforeEviction = try found(evicted)

        tracker.track(SignedUp(email: Sensitive("second@example.com"), note: Sensitive(String(repeating: "TRAF146-kept-note;", count: 170))))
        await tracker.flush()
        store.synchronize()

        let actualEvicted = try found(evicted)
        let actualKept = try found(kept)
        #expect(foundBeforeEviction)
        #expect(store.pendingRecordCount == 1)
        #expect(!actualEvicted)
        #expect(actualKept)
        await tracker.finish()
    }

    @Test("Rows recovery deletes, undecodable or over the bound, leave no byte of their Sensitive values behind, with secure_delete off", arguments: Journal.allCases)
    func recoveryDeletionsZeroed(journal: Journal) async throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("DatabaseStoreDeletionTests-\(UUID().uuidString)").string
        defer { try? FileManager.default.removeItem(atPath: directory) }
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let undecodable = Array("TRAF146-undecodable-note;".utf8)
        let evicted = Array("TRAF146-evicted-note;".utf8)
        let kept = Array("TRAF146-kept-note;".utf8)
        func found(_ marker: [UInt8]) throws -> Bool {
            try FileManager.default.contentsOfDirectory(atPath: directory).contains { name in
                FileManager.default.contents(atPath: directory + "/" + name).map { Array($0).firstRange(of: marker) != nil } ?? false
            }
        }
        let path = directory + "/records.sqlite"
        let database: any DatabaseWriter = journal == .rollback ? try DatabaseQueue(path: path) : try DatabasePool(path: path)
        try await database.writeWithoutTransaction { try $0.execute(sql: "PRAGMA secure_delete = 0") }
        do {
            let store = try DatabaseStore(events: [SignedUp.self, Retired.self], database: database)
            let tracker = Tracker(store: store)
            tracker.track(Retired(note: Sensitive(String(repeating: "TRAF146-undecodable-note;", count: 300))))
            tracker.track(SignedUp(email: Sensitive("first@example.com"), note: Sensitive(String(repeating: "TRAF146-evicted-note;", count: 360))))
            tracker.track(SignedUp(email: Sensitive("second@example.com"), note: Sensitive(String(repeating: "TRAF146-kept-note;", count: 420))))
            await tracker.finish()
            store.synchronize()
        }
        let foundBeforeRecovery = try [undecodable, evicted, kept].map(found)

        // Retired is no longer kept, so its row is undecodable; each other record's payload is
        // over 7,500 bytes, so the bound keeps the newest.
        let sut = try DatabaseStore(events: [SignedUp.self], database: database, byteBound: 10_000)
        sut.synchronize()

        let actual = try [undecodable, evicted, kept].map(found)
        let expected = [false, false, true]
        let expectedBeforeRecovery = [true, true, true]
        #expect(foundBeforeRecovery == expectedBeforeRecovery)
        #expect(sut.pendingRecordCount == 1)
        #expect(actual == expected)
    }
}

extension DatabaseStoreDeletionTests.SignedUp: Codable {}

extension DatabaseStoreDeletionTests.Retired: Codable {}
#endif
