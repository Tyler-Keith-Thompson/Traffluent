// Exit tests, in a file of their own: each runs its body in a child process, which iOS, tvOS,
// watchOS and visionOS cannot start.

import Events
import Foundation
import Persistence
import SystemPackage
import Testing
import TraffluentTestSupport

@Suite("SegmentStore: traps", .timeLimit(.minutes(1)))
struct SegmentStoreExitTests {
    struct Tapped: Event {}

    enum Renamed: Event {
        static let name = "Tapped"

        case only
    }

    @Test("A bound of 8 bytes, no more than a segment's header, traps", .tags(.precondition))
    func boundAtHeaderTraps() async {
        await #expect(processExitsWith: .failure) {
            _ = try? SegmentStore(events: [Tapped.self], directory: FilePath(NSTemporaryDirectory()).appending("SegmentStoreExitTests-\(UUID().uuidString)"), byteBound: 8)
        }
    }

    @Test("A bound of 9 bytes, one past the header, is accepted", .tags(.precondition))
    func boundPastHeader() async {
        await #expect(processExitsWith: .success) {
            let directory = FilePath(NSTemporaryDirectory()).appending("SegmentStoreExitTests-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(atPath: directory.string) }
            _ = try? SegmentStore(events: [Tapped.self], directory: directory, byteBound: 9)
        }
    }

    @Test("A segment size of 0 traps", .tags(.precondition))
    func zeroSegmentTraps() async {
        await #expect(processExitsWith: .failure) {
            _ = try? SegmentStore(events: [Tapped.self], directory: FilePath(NSTemporaryDirectory()).appending("SegmentStoreExitTests-\(UUID().uuidString)"), segmentByteCount: 0)
        }
    }

    @Test("Two event types under one name trap", .tags(.precondition))
    func duplicateNamesTrap() async {
        await #expect(processExitsWith: .failure) {
            _ = try? SegmentStore(events: [Tapped.self, Renamed.self], directory: FilePath(NSTemporaryDirectory()).appending("SegmentStoreExitTests-\(UUID().uuidString)"))
        }
    }

    @Test("One event type listed twice is accepted", .tags(.precondition))
    func repeatedType() async {
        await #expect(processExitsWith: .success) {
            let directory = FilePath(NSTemporaryDirectory()).appending("SegmentStoreExitTests-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(atPath: directory.string) }
            _ = try? SegmentStore(events: [Tapped.self, Tapped.self], directory: directory)
        }
    }
}

extension SegmentStoreExitTests.Tapped: BinaryCodable {
    func encode(to encoder: inout BinaryEncoder) {}

    init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {}
}

extension SegmentStoreExitTests.Renamed: BinaryCodable {
    func encode(to encoder: inout BinaryEncoder) {}

    init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
        self = .only
    }
}
