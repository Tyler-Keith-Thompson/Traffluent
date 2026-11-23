// Exit tests, in a file of their own: each runs its body in a child process, which some platforms
// (WASI) cannot start, and those builds leave out every file holding one.
//
// A child process opens a store, tracks and crashes (abort, so nothing gets to clean up); the
// parent then opens the same directory, as the app's next launch would.

import DestinationTesting
import Destinations
import Events
import Foundation
import Persistence
import SystemPackage
import Testing
import Trackers

@Suite("SegmentStore: crashes", .timeLimit(.minutes(1)))
struct SegmentStoreCrashExitTests {
    struct Tapped: Event, Equatable {
        var number: Int
    }

    /// Crashes the process as soon as it receives a batch, after the batch is delivered and
    /// before the delivery can acknowledge it.
    struct CrashingDestination: Destination {
        func receive(_ batch: [EventRecord]) async {
            abort()
        }
    }

    @Test("A record tracked right before the process crashes is delivered on the next launch, not marked redelivered")
    func crashAfterTrack() async throws {
        let path: String = FilePath(NSTemporaryDirectory()).appending("SegmentStoreCrashExitTests-\(UUID().uuidString)").string
        defer { try? FileManager.default.removeItem(atPath: path) }
        let destination = InMemoryDestination()
        let expected = [Tapped(number: 1), Tapped(number: 2)]

        await #expect(processExitsWith: .failure) { [path = path as String] in
            let tracker = Tracker(store: try! SegmentStore(events: [Tapped.self], directory: FilePath(path)))
            tracker.track(Tapped(number: 1))
            tracker.track(Tapped(number: 2))
            abort()
        }
        let store = try SegmentStore(events: [Tapped.self], directory: FilePath(path))
        let tracker = Tracker(store: store)
        tracker.finish()
        try await tracker.records.batch(strategy: .count(10)).deliver(to: destination).execute()

        #expect(destination.events(of: Tapped.self) == expected)
        #expect(destination.records.map(\.isRedelivered) == [false, false])
        #expect(store.byteCount == 0)
    }

    @Test("A batch delivered right before the process crashes, and so never deleted, is resent on the next launch marked redelivered")
    func crashAfterDelivery() async throws {
        let path: String = FilePath(NSTemporaryDirectory()).appending("SegmentStoreCrashExitTests-\(UUID().uuidString)").string
        defer { try? FileManager.default.removeItem(atPath: path) }
        let destination = InMemoryDestination()
        let expected = [Tapped(number: 1), Tapped(number: 2), Tapped(number: 3)]

        await #expect(processExitsWith: .failure) { [path = path as String] in
            let tracker = Tracker(store: try! SegmentStore(events: [Tapped.self], directory: FilePath(path)))
            tracker.track(Tapped(number: 1))
            tracker.track(Tapped(number: 2))
            tracker.track(Tapped(number: 3))
            try? await tracker.records.batch(strategy: .count(2)).deliver(to: CrashingDestination()).execute()
        }
        let store = try SegmentStore(events: [Tapped.self], directory: FilePath(path))
        let tracker = Tracker(store: store)
        tracker.finish()
        try await tracker.records.batch(strategy: .count(10)).deliver(to: destination).execute()

        #expect(destination.events(of: Tapped.self) == expected)
        #expect(destination.records.map(\.isRedelivered) == [true, true, false])
        #expect(store.byteCount == 0)
    }
}

extension SegmentStoreCrashExitTests.Tapped: BinaryCodable {
    func encode(to encoder: inout BinaryEncoder) {
        encoder.encode(number)
    }

    init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
        number = try decoder.decode()
    }
}
