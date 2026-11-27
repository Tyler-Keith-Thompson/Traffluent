import DiscoveryFixtures
import EventMacros
import Events
import Foundation
import Persistence
import Sessions
import SystemPackage
import Testing

#if canImport(GRDB)
    import GRDB
    import GRDBPersistence
#endif

@Event(name: "discovery_item_stored")
struct DiscoveryItemStored {
    var sku: String
}

/// An event that conforms by hand, which a store keeps only when it is listed.
struct DiscoveryStoredByHand: Event, Codable, Equatable {
    static let name = "discovery_stored_by_hand"
    var note: String
}

/// A hand-written event named as a discovered one is.
struct DiscoveryStoredClash: Event, Codable {
    static let name = "discovery_item_stored"
}

@Suite("Stores of every discovered event", .timeLimit(.minutes(1)))
struct DiscoveredStoreTests {
    @Test("SegmentStore() keeps the events of this module, of another module and of the library, and recovers each as its type")
    func segmentStore() throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("DiscoveredStoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        let earlier = try SegmentStore(directory: directory)
        let events: [any Event] = [DiscoveryItemStored(sku: "sku-1"), FixtureOpened(screen: "home"), SessionStarted()]
        let written = events.map { earlier.append(EventRecord(event: $0, timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location)) }
        let expectedNames = ["discovery_item_stored", "fixture_opened", "SessionStarted"]

        let sut = try SegmentStore(directory: directory)

        let recovered = sut.takeRecoveredRecords()
        #expect(written.allSatisfy { $0.deliveryTag != nil })
        #expect(recovered.map { type(of: $0.event).name } == expectedNames)
        #expect((recovered.first?.event as? DiscoveryItemStored)?.sku == "sku-1")
        #expect((recovered.dropFirst().first?.event as? FixtureOpened)?.screen == "home")
    }

    @Test("SegmentStore(events:) keeps only the listed types, reporting the first record of a discovered one left out")
    func explicitSubset() async throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("DiscoveredStoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        let sut = try SegmentStore(events: [DiscoveryItemStored.self], directory: directory)
        var reports = sut.dropReports.makeAsyncIterator()
        let expected = DropReport.notPersisted(event: "fixture_opened")

        let kept = sut.append(EventRecord(event: DiscoveryItemStored(sku: "sku-1"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location))
        let unlisted = sut.append(EventRecord(event: FixtureOpened(screen: "home"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location))

        #expect(kept.deliveryTag != nil)
        #expect(unlisted.deliveryTag == nil)
        #expect(await reports.next() == expected)
    }

    @Test("A hand-written event listed beside the discovered ones is kept too")
    func handWrittenListed() throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("DiscoveredStoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        let earlier = try SegmentStore(events: DiscoveredEvent.all.map(\.type) + [DiscoveryStoredByHand.self], directory: directory)
        _ = earlier.append(EventRecord(event: DiscoveryStoredByHand(note: "kept"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location))
        let expected = [DiscoveryStoredByHand(note: "kept")]

        let sut = try SegmentStore(events: DiscoveredEvent.all.map(\.type) + [DiscoveryStoredByHand.self], directory: directory)

        #expect(sut.takeRecoveredRecords().compactMap { $0.event as? DiscoveryStoredByHand } == expected)
    }

    @Test("SegmentStore() leaves out a hand-written event, kept in memory and reported")
    func handWrittenNotDiscovered() async throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("DiscoveredStoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        let sut = try SegmentStore(directory: directory)
        var reports = sut.dropReports.makeAsyncIterator()
        let expected = DropReport.notPersisted(event: "discovery_stored_by_hand")

        let actual = sut.append(EventRecord(event: DiscoveryStoredByHand(note: "memory"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location))

        #expect(actual.deliveryTag == nil)
        #expect(await reports.next() == expected)
    }

    @Test("A hand-written event named as a discovered one makes the list throw duplicateEventName")
    func duplicateName() {
        let directory = FilePath(NSTemporaryDirectory()).appending("DiscoveredStoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let events = DiscoveredEvent.all.map(\.type) + [DiscoveryStoredClash.self]
        let expected = SegmentStoreError.duplicateEventName(
            "discovery_item_stored", firstType: "EventDiscoveryTests.DiscoveryItemStored",
            secondType: "EventDiscoveryTests.DiscoveryStoredClash")

        #expect(throws: expected) {
            try SegmentStore(events: events, directory: directory)
        }
    }

    @Test("SegmentStore() throws as SegmentStore(events:) does for a bound no larger than a segment's header")
    func listFreeArguments() {
        let directory = FilePath(NSTemporaryDirectory()).appending("DiscoveredStoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let largestRefused = 8

        #expect(throws: SegmentStoreError.byteBoundTooSmall) {
            try SegmentStore(directory: directory, byteBound: largestRefused)
        }
        #expect(throws: SegmentStoreError.nonPositiveSegmentByteCount) {
            try SegmentStore(directory: directory, segmentByteCount: 0)
        }
        #expect(throws: Never.self) {
            try SegmentStore(directory: directory, byteBound: largestRefused + 1, segmentByteCount: 1)
        }
    }

    #if canImport(GRDB)
        @Test("DatabaseStore(database:) keeps the events of this module, of another module and of the library, and recovers each as its type")
        func databaseStore() throws {
            let database = try DatabaseQueue()
            let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
            let earlier = try DatabaseStore(database: database)
            let events: [any Event] = [DiscoveryItemStored(sku: "sku-1"), FixtureOpened(screen: "home"), SessionStarted()]
            let written = events.map { earlier.append(EventRecord(event: $0, timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location)) }
            let expectedNames = ["discovery_item_stored", "fixture_opened", "SessionStarted"]

            let sut = try DatabaseStore(database: database)

            let recovered = sut.takeRecoveredRecords()
            #expect(written.allSatisfy { $0.deliveryTag != nil })
            #expect(recovered.map { type(of: $0.event).name } == expectedNames)
            #expect((recovered.dropFirst().first?.event as? FixtureOpened)?.screen == "home")
        }

        @Test("DatabaseStore(database:) leaves out a hand-written event, kept in memory and reported")
        func databaseStoreHandWritten() async throws {
            let database = try DatabaseQueue()
            let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
            let sut = try DatabaseStore(database: database)
            var reports = sut.dropReports.makeAsyncIterator()
            let expected = DropReport.notPersisted(event: "discovery_stored_by_hand")

            let actual = sut.append(EventRecord(event: DiscoveryStoredByHand(note: "memory"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location))

            #expect(actual.deliveryTag == nil)
            #expect(await reports.next() == expected)
        }

        @Test("DatabaseStore(database:) throws as DatabaseStore(events:) does for a bound that isn't positive")
        func databaseStoreArguments() throws {
            let database = try DatabaseQueue()
            let largestRefused = 0

            #expect {
                try DatabaseStore(database: database, byteBound: largestRefused)
            } throws: { error in
                guard case DatabaseStoreError.nonPositiveByteBound = error else { return false }
                return true
            }
            #expect(throws: Never.self) {
                try DatabaseStore(database: database, byteBound: largestRefused + 1)
            }
        }
    #endif
}
