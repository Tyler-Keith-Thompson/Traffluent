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
// store or a plan of every discovered event refuses them: a store keeps the highest version of a
// name (EventDiscoveryVersionsTests), but two types at any one version still clash. They are
// declared out of order, so DiscoveredEvent.all's order comes from its sort, not from the order of
// their records.
//
// They sit in a private enum: @Event leaves a private type's events out of the link check of
// names, which would otherwise refuse the binary, so the run-time checks are what these tests
// see. Their fully qualified names then hold the address of the enum's context, so the expected
// names are read with String(reflecting:) rather than written out.
private enum Duplicates {
    @Event(name: "duplicated", version: 2)
    struct DuplicatedGamma {}

    @Event(name: "duplicated")
    struct DuplicatedBeta {}

    @Event(name: "duplicated")
    struct DuplicatedAlpha {}
}

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
            "\(String(reflecting: Duplicates.DuplicatedAlpha.self)) duplicated v1",
            "\(String(reflecting: Duplicates.DuplicatedBeta.self)) duplicated v1",
            "\(String(reflecting: Duplicates.DuplicatedGamma.self)) duplicated v2",
        ]

        let actual = DiscoveredEvent.all.map { "\(String(reflecting: $0.type)) \($0.type.name) v\($0.type.schemaVersion)" }

        #expect(actual == expected)
    }

    @Test("SegmentStore() throws duplicateEventName naming the two discovered types of one name and version, though a higher version is there to keep")
    func segmentStore() {
        let directory = FilePath(NSTemporaryDirectory()).appending("DiscoveredDuplicateTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let expected = SegmentStoreError.duplicateEventName(
            "duplicated", firstType: String(reflecting: Duplicates.DuplicatedAlpha.self),
            secondType: String(reflecting: Duplicates.DuplicatedBeta.self))

        #expect(throws: expected) {
            try SegmentStore(directory: directory)
        }
    }

    @Test("SegmentStore() reports a bound no larger than a segment's header before the duplicate names")
    func segmentStoreBoundFirst() {
        let directory = FilePath(NSTemporaryDirectory()).appending("DiscoveredDuplicateTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let largestRefused = 8

        #expect(throws: SegmentStoreError.byteBoundTooSmall) {
            try SegmentStore(directory: directory, byteBound: largestRefused)
        }
    }

    @Test("SegmentStore(events:) still opens with a list that leaves the duplicates out")
    func segmentStoreSubset() {
        let directory = FilePath(NSTemporaryDirectory()).appending("DiscoveredDuplicateTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }

        #expect(throws: Never.self) {
            try SegmentStore(events: [Unique.self, Duplicates.DuplicatedAlpha.self], directory: directory)
        }
    }

    @Test("TrackingPlan() throws duplicateEvent naming the two discovered types of one name and version")
    func trackingPlan() {
        let expected = TrackingPlanError.duplicateEvent(
            "duplicated", version: 1, firstType: String(reflecting: Duplicates.DuplicatedAlpha.self),
            secondType: String(reflecting: Duplicates.DuplicatedBeta.self))

        #expect(throws: expected) {
            try TrackingPlan()
        }
    }

    @Test("A plan of one version of each name is accepted, so only one name and version refuses a plan")
    func trackingPlanVersions() throws {
        let schemas = [Duplicates.DuplicatedAlpha.schema, Duplicates.DuplicatedGamma.schema, Alone.schema]

        let actual = try TrackingPlan(schemas: schemas).schemas.map(\.version)

        #expect(actual == [1, 1, 2])
    }

    #if canImport(GRDB)
        @Test("DatabaseStore(database:) throws duplicateEventName naming the two discovered types of one name and version, though a higher version is there to keep")
        func databaseStore() throws {
            let database = try DatabaseQueue()
            let expected = ["duplicated", String(reflecting: Duplicates.DuplicatedAlpha.self), String(reflecting: Duplicates.DuplicatedBeta.self)]

            let actual = #expect(throws: DatabaseStoreError.self) {
                try DatabaseStore(database: database)
            }

            guard case .duplicateEventName(let name, let firstType, let secondType) = actual else {
                Issue.record("Expected duplicateEventName, not \(String(describing: actual))")
                return
            }
            #expect([name, firstType, secondType] == expected)
        }

        @Test("DatabaseStore(database:) reports a bound that isn't positive before the duplicate names")
        func databaseStoreBoundFirst() throws {
            let database = try DatabaseQueue()
            let largestRefused = 0

            #expect {
                try DatabaseStore(database: database, byteBound: largestRefused)
            } throws: { error in
                guard case DatabaseStoreError.nonPositiveByteBound = error else { return false }
                return true
            }
        }
    #endif
}
