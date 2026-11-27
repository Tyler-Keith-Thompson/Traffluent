#if canImport(GRDB)
import Events
import GRDB
import GRDBPersistence
import Persistence
import Testing

@Suite("DatabaseStore: arguments", .timeLimit(.minutes(1)))
struct DatabaseStoreArgumentTests {
    struct Tapped: Event {}

    enum Renamed: Event {
        static let name = "Tapped"

        case only
    }

    @Test("A bound of zero or less throws nonPositiveByteBound", arguments: [0, -1, Int.min])
    func boundNotPositive(byteBound: Int) throws {
        let database = try DatabaseQueue()

        let actual = #expect(throws: DatabaseStoreError.self) {
            _ = try DatabaseStore(events: [Tapped.self], database: database, byteBound: byteBound)
        }

        guard case .nonPositiveByteBound = actual else {
            Issue.record("Expected nonPositiveByteBound, not \(String(describing: actual))")
            return
        }
    }

    @Test("A bound of 1 byte is accepted")
    func oneByteBound() throws {
        let database = try DatabaseQueue()
        let expected = 0

        let sut = try DatabaseStore(events: [Tapped.self], database: database, byteBound: 1)

        #expect(sut.byteCount == expected)
    }

    @Test("Two event types under one name throw duplicateEventName naming it and both types, in list order")
    func duplicateNames() throws {
        let database = try DatabaseQueue()
        let expectedName = "Tapped"
        let expectedFirstType = "PersistenceTests.DatabaseStoreArgumentTests.Renamed"
        let expectedSecondType = "PersistenceTests.DatabaseStoreArgumentTests.Tapped"

        let actual = #expect(throws: DatabaseStoreError.self) {
            _ = try DatabaseStore(events: [Renamed.self, Tapped.self], database: database)
        }

        guard case .duplicateEventName(let name, let firstType, let secondType) = actual else {
            Issue.record("Expected duplicateEventName, not \(String(describing: actual))")
            return
        }
        #expect(name == expectedName)
        #expect(firstType == expectedFirstType)
        #expect(secondType == expectedSecondType)
    }

    @Test("One event type listed twice is one type, and accepted")
    func repeatedType() throws {
        let database = try DatabaseQueue()
        let expected = 0

        let sut = try DatabaseStore(events: [Tapped.self, Tapped.self], database: database)

        #expect(sut.pendingRecordCount == expected)
    }
}

extension DatabaseStoreArgumentTests.Tapped: Codable {}

extension DatabaseStoreArgumentTests.Renamed: Codable {
    private enum CodingKeys: CodingKey {}

    func encode(to encoder: any Encoder) throws {
        _ = encoder.container(keyedBy: CodingKeys.self)
    }

    init(from decoder: any Decoder) throws {
        _ = try decoder.container(keyedBy: CodingKeys.self)
        self = .only
    }
}
#endif
