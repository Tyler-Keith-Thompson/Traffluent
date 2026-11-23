// Exit tests, in a file of their own: each runs its body in a child process, which iOS, tvOS,
// watchOS and visionOS cannot start.

#if canImport(GRDB)
import Events
import GRDB
import GRDBPersistence
import Persistence
import Testing
import TraffluentTestSupport

@Suite("DatabaseStore: traps", .timeLimit(.minutes(1)))
struct DatabaseStoreExitTests {
    struct Tapped: Event {}

    enum Renamed: Event {
        static let name = "Tapped"

        case only
    }

    @Test("A bound of 0 bytes traps", .tags(.precondition))
    func zeroBoundTraps() async {
        await #expect(processExitsWith: .failure) {
            _ = try? DatabaseStore(events: [Tapped.self], database: try! DatabaseQueue(), byteBound: 0)
        }
    }

    @Test("A bound of 1 byte is accepted", .tags(.precondition))
    func oneByteBound() async {
        await #expect(processExitsWith: .success) {
            _ = try? DatabaseStore(events: [Tapped.self], database: try! DatabaseQueue(), byteBound: 1)
        }
    }

    @Test("Two event types under one name trap", .tags(.precondition))
    func duplicateNamesTrap() async {
        await #expect(processExitsWith: .failure) {
            _ = try? DatabaseStore(events: [Tapped.self, Renamed.self], database: try! DatabaseQueue())
        }
    }
}

extension DatabaseStoreExitTests.Tapped: BinaryCodable {
    func encode(to encoder: inout BinaryEncoder) {}

    init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {}
}

extension DatabaseStoreExitTests.Renamed: BinaryCodable {
    func encode(to encoder: inout BinaryEncoder) {}

    init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
        self = .only
    }
}
#endif
