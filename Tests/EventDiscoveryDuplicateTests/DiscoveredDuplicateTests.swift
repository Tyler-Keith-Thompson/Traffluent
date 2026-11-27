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

// This target's binary holds three events named "duplicated", two of them at one version, so a
// store or a plan of every discovered event refuses them. They are declared out of order, so
// DiscoveredEvent.all's order comes from its sort, not from the order of their records.

@Event(name: "duplicated", version: 2)
struct DuplicatedGamma {}

@Event(name: "duplicated")
struct DuplicatedBeta {}

@Event(name: "duplicated")
struct DuplicatedAlpha {}

@Event(name: "alone")
struct Alone {}

@Event(name: "Unique")
struct Unique {}

@Suite("Discovered events sharing a name")
struct DiscoveredDuplicateTests {
    @Test("all orders events by name, then version, then fully qualified type name")
    func order() {
        let expected = [
            "\(String(reflecting: Unique.self)) Unique v1",
            "\(String(reflecting: Alone.self)) alone v1",
            "\(String(reflecting: DuplicatedAlpha.self)) duplicated v1",
            "\(String(reflecting: DuplicatedBeta.self)) duplicated v1",
            "\(String(reflecting: DuplicatedGamma.self)) duplicated v2",
        ]

        let actual = DiscoveredEvent.all.map { "\(String(reflecting: $0.type)) \($0.type.name) v\($0.type.schemaVersion)" }

        #expect(actual == expected)
    }

    @Test("SegmentStore() throws duplicateEventName naming the first two discovered types of one name")
    func segmentStore() {
        let directory = FilePath(NSTemporaryDirectory()).appending("DiscoveredDuplicateTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let expected = SegmentStoreError.duplicateEventName(
            "duplicated", firstType: "EventDiscoveryDuplicateTests.DuplicatedAlpha",
            secondType: "EventDiscoveryDuplicateTests.DuplicatedBeta")

        #expect(throws: expected) {
            try SegmentStore(directory: directory)
        }
    }

    @Test("SegmentStore(events:) still opens with a list that leaves the duplicates out")
    func segmentStoreSubset() {
        let directory = FilePath(NSTemporaryDirectory()).appending("DiscoveredDuplicateTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }

        #expect(throws: Never.self) {
            try SegmentStore(events: [Unique.self, DuplicatedAlpha.self], directory: directory)
        }
    }

    @Test("TrackingPlan() throws duplicateEvent naming the two discovered types of one name and version")
    func trackingPlan() {
        let expected = TrackingPlanError.duplicateEvent(
            "duplicated", version: 1, firstType: "EventDiscoveryDuplicateTests.DuplicatedAlpha",
            secondType: "EventDiscoveryDuplicateTests.DuplicatedBeta")

        #expect(throws: expected) {
            try TrackingPlan()
        }
    }

    @Test("A plan of one version of each name is accepted, so only one name and version refuses a plan")
    func trackingPlanVersions() throws {
        let schemas = [DuplicatedAlpha.schema, DuplicatedGamma.schema, Alone.schema]

        let actual = try TrackingPlan(schemas: schemas).schemas.map(\.version)

        #expect(actual == [1, 1, 2])
    }

    #if canImport(GRDB)
        @Test("DatabaseStore(database:) throws duplicateEventName naming the first two discovered types of one name")
        func databaseStore() throws {
            let database = try DatabaseQueue()
            let expected = ["duplicated", "EventDiscoveryDuplicateTests.DuplicatedAlpha", "EventDiscoveryDuplicateTests.DuplicatedBeta"]

            let actual = #expect(throws: DatabaseStoreError.self) {
                try DatabaseStore(database: database)
            }

            guard case .duplicateEventName(let name, let firstType, let secondType) = actual else {
                Issue.record("Expected duplicateEventName, not \(String(describing: actual))")
                return
            }
            #expect([name, firstType, secondType] == expected)
        }
    #endif
}
