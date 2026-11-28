import EventMacros
import Events
import Foundation
import Persistence
import SystemPackage
import Testing
import TrackingPlans

#if canImport(GRDB)
    import GRDB
    import GRDBPersistence
#endif

// This target's binary declares two versions of "checkout_started", as a relay that reads older
// apps' batches does: the current one at file scope, the earlier one in a file-scope private enum,
// which @Event leaves out of the link check of names. The list-free stores keep the newest; an
// explicit list naming both still refuses them.

@Event(name: "checkout_started", version: 2)
struct CheckoutStarted: Equatable {
    var items: Int
    var currency: String
}

// Version 1, which releases still installed send.
private enum EarlierVersions {
    @Event(name: "checkout_started")
    struct CheckoutStarted {
        var items: Int
    }
}

@Suite("Stores of every discovered event, two versions of one name among them", .timeLimit(.minutes(1)))
struct DiscoveredVersionsTests {
    @Test("The binary holds both versions, so the tests below see two discovered types of one name")
    func bothDiscovered() {
        let expected = [1, 2]

        let actual = DiscoveredEvent.all.filter { $0.type.name == "checkout_started" }.map { $0.type.schemaVersion }

        #expect(actual == expected)
    }

    @Test("SegmentStore() opens, writes the highest version and recovers it as that type")
    func segmentStoreKeepsHighest() throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("DiscoveredVersionsTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        let earlier = try SegmentStore(directory: directory)
        let written = earlier.append(EventRecord(event: CheckoutStarted(items: 2, currency: "EUR"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location))
        let expected = [CheckoutStarted(items: 2, currency: "EUR")]

        let sut = try SegmentStore(directory: directory)

        let actual = sut.takeRecoveredRecords().compactMap { $0.event as? CheckoutStarted }
        #expect(written.deliveryTag != nil)
        #expect(actual == expected)
    }

    @Test("SegmentStore() keeps an event of the earlier version's type in memory only, reported as not persisted")
    func segmentStoreLeavesEarlierOut() async throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("DiscoveredVersionsTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        let sut = try SegmentStore(directory: directory)
        var reports = sut.dropReports.makeAsyncIterator()
        let expected = DropReport.notPersisted(event: "checkout_started")

        let actual = sut.append(EventRecord(event: EarlierVersions.CheckoutStarted(items: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location))

        #expect(actual.deliveryTag == nil)
        #expect(await reports.next() == expected)
    }

    @Test("A record stored at the earlier version before an upgrade is dropped by SegmentStore() as a version mismatch, not read as the highest")
    func segmentStoreDropsStoredEarlier() async throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("DiscoveredVersionsTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        do {
            let beforeUpgrade = try SegmentStore(events: [EarlierVersions.CheckoutStarted.self], directory: directory)
            _ = beforeUpgrade.append(EventRecord(event: EarlierVersions.CheckoutStarted(items: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location))
        }
        let expected = DropReport.versionMismatch(event: "checkout_started", storedVersion: 1, currentVersion: 2, recordCount: 1)

        let sut = try SegmentStore(directory: directory)

        var reports = sut.dropReports.makeAsyncIterator()
        #expect(sut.takeRecoveredRecords().isEmpty)
        #expect(await reports.next() == expected)
    }

    @Test("SegmentStore(events:) listing both versions still throws duplicateEventName, as the caller chose the list")
    func segmentStoreExplicitList() {
        let directory = FilePath(NSTemporaryDirectory()).appending("DiscoveredVersionsTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let expected = SegmentStoreError.duplicateEventName(
            "checkout_started", firstType: String(reflecting: EarlierVersions.CheckoutStarted.self),
            secondType: String(reflecting: CheckoutStarted.self))

        #expect(throws: expected) {
            try SegmentStore(events: [EarlierVersions.CheckoutStarted.self, CheckoutStarted.self], directory: directory)
        }
    }

    @Test("TrackingPlan() in the same program holds both versions")
    func trackingPlan() throws {
        let expected = [1, 2]

        let actual = try TrackingPlan().schemas.filter { $0.name == "checkout_started" }.map(\.version)

        #expect(actual == expected)
    }

    #if canImport(GRDB)
        @Test("DatabaseStore(database:) opens, writes the highest version and recovers it as that type")
        func databaseStoreKeepsHighest() throws {
            let database = try DatabaseQueue()
            let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
            let earlier = try DatabaseStore(database: database)
            let written = earlier.append(EventRecord(event: CheckoutStarted(items: 2, currency: "EUR"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location))
            let expected = [CheckoutStarted(items: 2, currency: "EUR")]

            let sut = try DatabaseStore(database: database)

            let actual = sut.takeRecoveredRecords().compactMap { $0.event as? CheckoutStarted }
            #expect(written.deliveryTag != nil)
            #expect(actual == expected)
        }

        @Test("DatabaseStore(database:) keeps an event of the earlier version's type in memory only, reported as not persisted")
        func databaseStoreLeavesEarlierOut() async throws {
            let database = try DatabaseQueue()
            let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
            let sut = try DatabaseStore(database: database)
            var reports = sut.dropReports.makeAsyncIterator()
            let expected = DropReport.notPersisted(event: "checkout_started")

            let actual = sut.append(EventRecord(event: EarlierVersions.CheckoutStarted(items: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location))

            #expect(actual.deliveryTag == nil)
            #expect(await reports.next() == expected)
        }

        @Test("A record stored at the earlier version before an upgrade is dropped by DatabaseStore(database:) as a version mismatch")
        func databaseStoreDropsStoredEarlier() async throws {
            let database = try DatabaseQueue()
            let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
            do {
                let beforeUpgrade = try DatabaseStore(events: [EarlierVersions.CheckoutStarted.self], database: database)
                _ = beforeUpgrade.append(EventRecord(event: EarlierVersions.CheckoutStarted(items: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location))
            }
            let expected = DropReport.versionMismatch(event: "checkout_started", storedVersion: 1, currentVersion: 2, recordCount: 1)

            let sut = try DatabaseStore(database: database)

            var reports = sut.dropReports.makeAsyncIterator()
            #expect(sut.takeRecoveredRecords().isEmpty)
            #expect(await reports.next() == expected)
        }

        @Test("DatabaseStore(events:database:) listing both versions still throws duplicateEventName")
        func databaseStoreExplicitList() throws {
            let database = try DatabaseQueue()
            let expected = ["checkout_started", String(reflecting: EarlierVersions.CheckoutStarted.self), String(reflecting: CheckoutStarted.self)]

            let actual = #expect(throws: DatabaseStoreError.self) {
                try DatabaseStore(events: [EarlierVersions.CheckoutStarted.self, CheckoutStarted.self], database: database)
            }

            guard case .duplicateEventName(let name, let firstType, let secondType) = actual else {
                Issue.record("Expected duplicateEventName, not \(String(describing: actual))")
                return
            }
            #expect([name, firstType, secondType] == expected)
        }
    #endif
}
