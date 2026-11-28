import Destinations
import Events
import Foundation
import Instrumentation
import Persistence
import PropertyBased
import Testing
import Trackers
import TraffluentTestSupport

#if canImport(GRDB)
import GRDB
#endif

// A record's session is kept beside it, in its own bytes, so a record recovered after a relaunch
// goes to a vendor under the identity it was first sent with (TRAF-122). Run against each kind of
// store (StoreKind); a second store opened on a copy of the directory is the next launch.

@Suite("RecordStore: sessions", .timeLimit(.minutes(1)))
struct RecordStoreSessionTests {
    struct Tapped: Event, Equatable {
        var number: Int
    }

    @Test("A record tracked in a session is recovered on the next launch with the SessionKey it was tracked with", arguments: StoreKind.all)
    func recoveredWithSession(kind: StoreKind) async throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let expected = UUID(uuidString: "019A2B3C-4D5E-7F60-8172-839405A6B7C8")!
        let session = Enricher { $0[SessionKey.self] = expected }
        let tracker = Tracker(store: try kind.open(at: path, events: [Tapped.self]).store, enrichers: [session])
        tracker.track(Tapped(number: 1))
        await tracker.finish()
        let copy = path + "-copy"
        defer { try? FileManager.default.removeItem(atPath: copy) }
        try FileManager.default.copyItem(atPath: path, toPath: copy)

        let recovered = try kind.open(at: copy, events: [Tapped.self]).store.takeRecoveredRecords()

        let actual = try #require(recovered.first)
        #expect(recovered.count == 1)
        #expect(actual.context[SessionKey.self] == expected)
    }

    @Test("A tracker started on the next launch delivers a recovered record with its own session, not the new tracker's", arguments: StoreKind.all)
    func recoveredKeepsItsSessionThroughTheNextTracker(kind: StoreKind) async throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let expectedEarlier = UUID(uuidString: "019A2B3C-4D5E-7F60-8172-839405A6B7C8")!
        let expectedLater = UUID(uuidString: "019A2B3C-9999-7F60-8172-839405A6B7C8")!
        let earlier = Tracker(store: try kind.open(at: path, events: [Tapped.self]).store, enrichers: [Enricher { $0[SessionKey.self] = expectedEarlier }])
        earlier.track(Tapped(number: 1))
        await earlier.finish()
        let copy = path + "-copy"
        defer { try? FileManager.default.removeItem(atPath: copy) }
        try FileManager.default.copyItem(atPath: path, toPath: copy)
        let sut = Tracker(store: try kind.open(at: copy, events: [Tapped.self]).store, enrichers: [Enricher { $0[SessionKey.self] = expectedLater }])
        let destination = InMemoryDestination()

        sut.track(Tapped(number: 2))
        await sut.finish()
        try await sut.records.batch(strategy: .count(10)).deliver(to: destination).execute()

        let actual = destination.records.map { $0.context[SessionKey.self] }
        #expect(destination.records.compactMap { ($0.event as? Tapped)?.number } == [1, 2])
        #expect(actual == [expectedEarlier, expectedLater])
    }

    @Test("Records with and without a session in one store each come back with their own, or none", arguments: StoreKind.all)
    func eachRecordItsOwnSession(kind: StoreKind) throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let first = UUID(uuidString: "019A2B3C-4D5E-7F60-8172-839405A6B7C8")!
        let second = UUID(uuidString: "019A2B3D-0000-7000-8000-000000000001")!
        let expected: [UUID?] = [first, nil, second, first]
        let store = try kind.open(at: path, events: [Tapped.self]).store
        for (number, session) in expected.enumerated() {
            var context = ServiceContext.topLevel
            context[SessionKey.self] = session
            _ = store.append(EventRecord(event: Tapped(number: number), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil, context: context))
        }
        let copy = path + "-copy"
        defer { try? FileManager.default.removeItem(atPath: copy) }
        try FileManager.default.copyItem(atPath: path, toPath: copy)

        let recovered = try kind.open(at: copy, events: [Tapped.self]).store.takeRecoveredRecords()

        let actual = recovered.map { $0.context[SessionKey.self] }
        #expect(recovered.compactMap { ($0.event as? Tapped)?.number } == [0, 1, 2, 3])
        #expect(actual == expected)
    }

    @Test("A sessionless record comes back with no session and an otherwise empty context", arguments: StoreKind.all)
    func sessionlessStaysSessionless(kind: StoreKind) throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let store = try kind.open(at: path, events: [Tapped.self]).store
        _ = store.append(EventRecord(event: Tapped(number: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil))
        let copy = path + "-copy"
        defer { try? FileManager.default.removeItem(atPath: copy) }
        try FileManager.default.copyItem(atPath: path, toPath: copy)

        let actual = try #require(try kind.open(at: copy, events: [Tapped.self]).store.takeRecoveredRecords().first)

        #expect(actual.context[SessionKey.self] == nil)
        #expect(actual.context.isEmpty)
    }

    @Test("A key of the app's own in a record's context comes back absent beside its session, as a store keeps only its listed keys", arguments: StoreKind.all)
    func ownKeyNotKeptBesideSession(kind: StoreKind) throws {
        enum RegionKey: ServiceContextKey {
            typealias Value = String
        }
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let expected = UUID(uuidString: "019A2B3C-4D5E-7F60-8172-839405A6B7C8")!
        var context = ServiceContext.topLevel
        context[SessionKey.self] = expected
        context[RegionKey.self] = "eu-west"
        let store = try kind.open(at: path, events: [Tapped.self]).store
        _ = store.append(EventRecord(event: Tapped(number: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil, context: context))
        let copy = path + "-copy"
        defer { try? FileManager.default.removeItem(atPath: copy) }
        try FileManager.default.copyItem(atPath: path, toPath: copy)

        let actual = try #require(try kind.open(at: copy, events: [Tapped.self]).store.takeRecoveredRecords().first)

        #expect(actual.context[SessionKey.self] == expected)
        #expect(actual.context[RegionKey.self] == nil)
        #expect(actual.context.count == 1)
    }

    @Test("A record read back by its position, as for a batch a full destination buffer dropped, keeps its session", arguments: StoreKind.all)
    func readBackWithSession(kind: StoreKind) throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let expected = UUID(uuidString: "019A2B3C-4D5E-7F60-8172-839405A6B7C8")!
        var context = ServiceContext.topLevel
        context[SessionKey.self] = expected
        let store = try kind.open(at: path, events: [Tapped.self]).store
        let tag = try #require(store.append(EventRecord(event: Tapped(number: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil, context: context)).deliveryTag)

        let readBack = tag.acknowledger.records(at: [tag.position])

        let actual = try #require(readBack.first)
        #expect(readBack.count == 1)
        #expect(actual.context[SessionKey.self] == expected)
    }

    @Test("A stored session is deleted with its record once delivered: a segment store's files, or a database store's rows, hold it before and not after", arguments: StoreKind.all)
    func deletedWithItsRecord(kind: StoreKind) async throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let session = UUID(uuidString: "019A2B3C-4D5E-7F60-8172-839405A6B7C8")!
        // The form the record map holds it in, UUID's Codable string.
        let needle = Array(session.uuidString.utf8)
        // What the store keeps: every file's bytes for a segment store, every row's payload for a
        // database store.
        func stored() throws -> [[UInt8]] {
            switch kind {
            case .segments:
                return try FileManager.default.contentsOfDirectory(atPath: path).compactMap { name in
                    FileManager.default.contents(atPath: path + "/" + name).map(Array.init)
                }
            #if canImport(GRDB)
            case .databaseQueue, .databasePool:
                let database = try DatabaseQueue(path: path + "/records.sqlite")
                return try database.read { db in
                    try Data.fetchAll(db, sql: "SELECT payload FROM traffluentRecord").map(Array.init)
                }
            #endif
            }
        }
        let store = try kind.open(at: path, events: [Tapped.self]).store
        let tracker = Tracker(store: store, enrichers: [Enricher { $0[SessionKey.self] = session }])
        let destination = InMemoryDestination()
        tracker.track(Tapped(number: 1))
        tracker.track(Tapped(number: 2))
        await tracker.flush()
        store.synchronize()
        let storedBefore = try stored()

        await tracker.finish()
        try await tracker.records.batch(strategy: .count(10)).deliver(to: destination).execute()
        store.synchronize()

        let storedAfter = try stored()
        let actualDelivered = destination.records.map { $0.context[SessionKey.self] }
        let heldBefore = storedBefore.contains { $0.firstRange(of: needle) != nil }
        let heldAfter = storedAfter.contains { $0.firstRange(of: needle) != nil }
        #expect(actualDelivered == [session, session])
        #expect(heldBefore)
        #expect(!heldAfter)
        #expect(store.pendingRecordCount == 0)
    }

    @Test("Any mix of records with and without sessions comes back on the next launch, each with the session it was stored with", .tags(.randomized), arguments: StoreKind.all)
    func randomSessionsRoundTrip(kind: StoreKind) async {
        await propertyCheck(count: 40, input: Gen.uint8().optional.array(of: 0...12)) { picks in
            let path = StoreKind.temporaryPath()
            defer { try? FileManager.default.removeItem(atPath: path) }
            // Few distinct sessions, so records share them as a session's records do.
            let expected: [UUID?] = picks.map { pick in
                pick.map { UUID(uuid: (0x01, 0x9A, 0, 0, 0, 0, 0x70, 0, 0x80, 0, 0, 0, 0, 0, 0, $0 % 4)) }
            }
            let store = try kind.open(at: path, events: [Tapped.self]).store
            for (number, session) in expected.enumerated() {
                var context = ServiceContext.topLevel
                context[SessionKey.self] = session
                _ = store.append(EventRecord(event: Tapped(number: number), timestamp: Date(timeIntervalSince1970: Double(number)), sourceLocation: nil, context: context))
            }
            let copy = path + "-copy"
            defer { try? FileManager.default.removeItem(atPath: copy) }
            try FileManager.default.copyItem(atPath: path, toPath: copy)

            let recovered = try kind.open(at: copy, events: [Tapped.self]).store.takeRecoveredRecords()

            let actualNumbers = recovered.compactMap { ($0.event as? Tapped)?.number }
            let actual = recovered.map { $0.context[SessionKey.self] }
            #expect(actualNumbers == Array(expected.indices))
            #expect(actual == expected)
        }
    }
}

extension RecordStoreSessionTests.Tapped: Codable {}
