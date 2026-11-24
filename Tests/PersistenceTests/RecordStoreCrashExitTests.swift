// Exit tests, in a file of their own: each runs its body in a child process, which iOS, tvOS,
// watchOS and visionOS cannot start.
//
// A child process opens a store, tracks and crashes (abort, so nothing gets to clean up); the
// parent then opens the same store, as the app's next launch would. Each test runs against every
// kind of store (StoreKind).

import Destinations
import Events
import Dispatch
import Foundation
import Persistence
import Synchronization
import Testing
import Trackers

@Suite("RecordStore: crashes", .timeLimit(.minutes(1)))
struct RecordStoreCrashExitTests {
    struct Tapped: Event, Equatable {
        var number: Int
    }

    /// Counts its calls, from any thread.
    final class Count: Sendable {
        private let count = Mutex(0)

        /// One more than the last call returned, starting at 1.
        func next() -> Int {
            count.withLock { count in
                count += 1
                return count
            }
        }
    }

    /// Crashes the process as soon as it receives a batch, after the batch is delivered and
    /// before the delivery can acknowledge it.
    struct CrashingDestination: Destination {
        func receive(_ batch: [EventRecord]) async {
            abort()
        }
    }

    @Test("A record flushed right before the process crashes is delivered on the next launch, not marked redelivered", arguments: StoreKind.all)
    func crashAfterTrack(kind: StoreKind) async throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let destination = InMemoryDestination()
        let expected = [Tapped(number: 1), Tapped(number: 2)]

        await #expect(processExitsWith: .failure) { [kind = kind as StoreKind, path = path as String] in
            let tracker = Tracker(store: try! kind.open(at: path, events: [Tapped.self]).store)
            tracker.track(Tapped(number: 1))
            tracker.track(Tapped(number: 2))
            await tracker.flush()
            abort()
        }
        let store = try kind.open(at: path, events: [Tapped.self]).store
        let tracker = Tracker(store: store)
        await tracker.finish()
        try await tracker.records.batch(strategy: .count(10)).deliver(to: destination).execute()

        #expect(destination.events(of: Tapped.self) == expected)
        #expect(destination.records.map(\.isRedelivered) == [false, false])
        #expect(store.byteCount == 0)
    }

    @Test("A record the worker hasn't reached when the process crashes is lost: a record is durable once written, not once track returns", arguments: StoreKind.all)
    func crashBeforeWritten(kind: StoreKind) async throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let expected = [Tapped(number: 1)]

        await #expect(processExitsWith: .failure) { [kind = kind as StoreKind, path = path as String] in
            // Blocks the worker for good from the second event on, so the events after the
            // first are tracked but never reached.
            let enriched = Count()
            let (reached, reaching) = AsyncStream.makeStream(of: Void.self)
            let never = DispatchSemaphore(value: 0)
            let enricher = Enricher { _ in
                guard enriched.next() > 1 else { return }
                reaching.yield()
                never.wait()
            }
            let tracker = Tracker(store: try! kind.open(at: path, events: [Tapped.self]).store, enrichers: [enricher])
            tracker.track(Tapped(number: 1))
            await tracker.flush()
            tracker.track(Tapped(number: 2))
            tracker.track(Tapped(number: 3))
            var reachedSecond = reached.makeAsyncIterator()
            _ = await reachedSecond.next()
            abort()
        }
        let recovered = try kind.open(at: path, events: [Tapped.self]).store.takeRecoveredRecords()

        #expect(recovered.compactMap { $0.event as? Tapped } == expected)
    }

    @Test("A batch delivered right before the process crashes, and so never deleted, is resent on the next launch marked redelivered", arguments: StoreKind.all)
    func crashAfterDelivery(kind: StoreKind) async throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let destination = InMemoryDestination()
        let expected = [Tapped(number: 1), Tapped(number: 2), Tapped(number: 3)]

        await #expect(processExitsWith: .failure) { [kind = kind as StoreKind, path = path as String] in
            let tracker = Tracker(store: try! kind.open(at: path, events: [Tapped.self]).store)
            tracker.track(Tapped(number: 1))
            tracker.track(Tapped(number: 2))
            tracker.track(Tapped(number: 3))
            await tracker.flush()
            try? await tracker.records.batch(strategy: .count(2)).deliver(to: CrashingDestination()).execute()
        }
        let store = try kind.open(at: path, events: [Tapped.self]).store
        let tracker = Tracker(store: store)
        await tracker.finish()
        try await tracker.records.batch(strategy: .count(10)).deliver(to: destination).execute()

        #expect(destination.events(of: Tapped.self) == expected)
        #expect(destination.records.map(\.isRedelivered) == [true, true, false])
        #expect(store.byteCount == 0)
    }
}

extension RecordStoreCrashExitTests.Tapped: BinaryCodable {
    func encode(to encoder: inout BinaryEncoder) {
        encoder.encodeMap { map in
            map.encode(number, forKey: "number")
        }
    }

    init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
        var map = try decoder.decodeMap()
        number = try map.decode(forKey: "number")
    }
}
