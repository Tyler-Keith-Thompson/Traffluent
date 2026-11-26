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

    @Test("Two event types under one name throw duplicateEventName")
    func duplicateNames() throws {
        let database = try DatabaseQueue()

        let actual = #expect(throws: DatabaseStoreError.self) {
            _ = try DatabaseStore(events: [Tapped.self, Renamed.self], database: database)
        }

        guard case .duplicateEventName = actual else {
            Issue.record("Expected duplicateEventName, not \(String(describing: actual))")
            return
        }
    }

    @Test("One event type listed twice is one type, and accepted")
    func repeatedType() throws {
        let database = try DatabaseQueue()
        let expected = 0

        let sut = try DatabaseStore(events: [Tapped.self, Tapped.self], database: database)

        #expect(sut.pendingRecordCount == expected)
    }
}

extension DatabaseStoreArgumentTests.Tapped: BinaryCodable {
    func encode(to encoder: inout BinaryEncoder) {
        encoder.encodeMap { _ in }
    }

    init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
        _ = try decoder.decodeMap()
    }
}

extension DatabaseStoreArgumentTests.Renamed: BinaryCodable {
    func encode(to encoder: inout BinaryEncoder) {
        encoder.encodeMap { _ in }
    }

    init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
        _ = try decoder.decodeMap()
        self = .only
    }
}
#endif
