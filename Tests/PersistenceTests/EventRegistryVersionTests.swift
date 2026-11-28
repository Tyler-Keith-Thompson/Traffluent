import Events
import Persistence
import PropertyBased
import Testing
import TraffluentTestSupport

// The types conform by hand, so DiscoveredEvent.all never lists them and the list-free stores in
// this target's other suites don't see their shared names.
@Suite("EventRegistry: the newest version of each discovered name", .timeLimit(.minutes(1)))
struct EventRegistryVersionTests {
    struct OpenedV1: Event, Codable {
        static let name = "opened"
    }

    struct OpenedV2: Event, Codable {
        static let name = "opened"
        static let schemaVersion = 2
    }

    struct OpenedV2Again: Event, Codable {
        static let name = "opened"
        static let schemaVersion = 2
    }

    struct OpenedV3: Event, Codable {
        static let name = "opened"
        static let schemaVersion = 3
    }

    struct ClosedV1: Event, Codable {
        static let name = "closed"
    }

    struct ClosedV1Again: Event, Codable {
        static let name = "closed"
    }

    @Test("Of two versions of one name, the highest is kept whichever is listed first")
    func highestKept() throws {
        let expectedVersion = 2

        let sut = try EventRegistry(newestVersionsOf: [OpenedV2.self, OpenedV1.self])

        #expect(sut.registration(of: OpenedV2.self) != nil)
        #expect(sut.registration(of: OpenedV1.self) == nil)
        #expect(sut.registration(named: "opened")?.version == expectedVersion)
    }

    @Test("Of three versions of one name, only the highest is kept")
    func highestOfThree() throws {
        let expectedVersion = 3

        let sut = try EventRegistry(newestVersionsOf: [OpenedV1.self, OpenedV3.self, OpenedV2.self])

        #expect(sut.registration(of: OpenedV3.self) != nil)
        #expect(sut.registration(of: OpenedV2.self) == nil)
        #expect(sut.registration(of: OpenedV1.self) == nil)
        #expect(sut.registration(named: "opened")?.version == expectedVersion)
    }

    @Test("Each name keeps its own newest version")
    func namesApart() throws {
        let sut = try EventRegistry(newestVersionsOf: [ClosedV1.self, OpenedV1.self, OpenedV2.self])

        #expect(sut.registration(of: ClosedV1.self) != nil)
        #expect(sut.registration(of: OpenedV2.self) != nil)
        #expect(sut.registration(of: OpenedV1.self) == nil)
    }

    @Test("No types make an empty registry, and one type is kept")
    func emptyAndOne() throws {
        let empty = try EventRegistry(newestVersionsOf: [])
        let one = try EventRegistry(newestVersionsOf: [OpenedV1.self])

        #expect(empty.registration(named: "opened") == nil)
        #expect(one.registration(of: OpenedV1.self) != nil)
    }

    @Test("One type listed twice is one type, and accepted")
    func repeatedType() throws {
        let sut = try EventRegistry(newestVersionsOf: [OpenedV2.self, OpenedV1.self, OpenedV2.self])

        #expect(sut.registration(of: OpenedV2.self) != nil)
    }

    @Test("Two types of one name at the highest version throw DuplicateEventName naming both, in list order")
    func clashAtHighest() {
        let expected = ["opened", String(reflecting: OpenedV2.self), String(reflecting: OpenedV2Again.self)]

        let actual = #expect(throws: DuplicateEventName.self) {
            try EventRegistry(newestVersionsOf: [OpenedV1.self, OpenedV2.self, OpenedV2Again.self])
        }

        #expect(actual.map { [$0.name, $0.firstType, $0.secondType] } == expected)
    }

    @Test("Two types of one name at an earlier version throw too, though a higher one would be kept")
    func clashBelowHighest() {
        let expected = ["closed", String(reflecting: ClosedV1.self), String(reflecting: ClosedV1Again.self)]

        let actual = #expect(throws: DuplicateEventName.self) {
            try EventRegistry(newestVersionsOf: [ClosedV1.self, OpenedV3.self, ClosedV1Again.self])
        }

        #expect(actual.map { [$0.name, $0.firstType, $0.secondType] } == expected)
    }

    @Test("The explicit list's registry still refuses two versions of one name")
    func explicitListRefuses() {
        let expected = ["opened", String(reflecting: OpenedV1.self), String(reflecting: OpenedV2.self)]

        let actual = #expect(throws: DuplicateEventName.self) {
            try EventRegistry([OpenedV1.self, OpenedV2.self])
        }

        #expect(actual.map { [$0.name, $0.firstType, $0.secondType] } == expected)
    }

    @Test("The registry keeps what a naive reference keeps, and throws where it throws", .tags(.randomized))
    func matchesReference() async {
        let pool: [any (Event & Codable).Type] = [OpenedV1.self, OpenedV2.self, OpenedV2Again.self, OpenedV3.self, ClosedV1.self, ClosedV1Again.self]

        await propertyCheck(input: Gen.int(in: 0...(pool.count - 1)).array(of: 0...8)) { indices in
            let types = indices.map { pool[$0] }
            let expected = Reference.outcome(of: indices, in: pool)

            let actual: Reference.Outcome
            do throws(DuplicateEventName) {
                let sut = try EventRegistry(newestVersionsOf: types)
                actual = .kept(Set(pool.indices.filter { sut.registration(of: pool[$0]) != nil }))
            } catch {
                actual = .refused([error.name, error.firstType, error.secondType])
            }

            #expect(actual == expected)
        }
    }
}

/// The rule written out the slow way: every pair compared.
private enum Reference {
    enum Outcome: Equatable {
        case kept(Set<Int>)
        case refused([String])
    }

    static func outcome(of indices: [Int], in pool: [any (Event & Codable).Type]) -> Outcome {
        for (position, index) in indices.enumerated() {
            let type = pool[index]
            let earlier = indices.prefix(position).first { pool[$0].name == type.name && pool[$0].schemaVersion == type.schemaVersion }
            if let earlier, earlier != index {
                return .refused([type.name, String(reflecting: pool[earlier]), String(reflecting: type)])
            }
        }
        let kept = Set(indices.filter { index in
            indices.allSatisfy { pool[$0].name != pool[index].name || pool[$0].schemaVersion <= pool[index].schemaVersion }
        })
        return .kept(kept)
    }
}
