// Exit tests, in a file of their own: each runs its body in a child process, which some platforms
// (WASI) cannot start, and those builds leave out every file holding one.
//
// Each child makes the store's writes fail as a full disk does (OpenedStore.failWrites): for a
// segment store it lowers the process's file-size limit, for a database store it makes the
// connection read-only. Both are real failures, from the operating system or SQLite, with no seam
// in the store, and the child's alone, so they can't reach the other tests. A child exits 0 only
// if the store did what the test names; the parent then opens the store as the next launch would.
// Each test runs against every kind of store (StoreKind).

import DestinationTesting
import Destinations
import Events
import Foundation
import Persistence
import Testing
import Trackers

@Suite("RecordStore: write failures", .timeLimit(.minutes(1)))
struct RecordStoreWriteFailureExitTests {
    struct Tapped: Event, Equatable {
        var number: Int
    }

    @Test("A record whose write fails is kept in memory only and reported, and the records before it stay", arguments: StoreKind.all)
    func appendFails(kind: StoreKind) async throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }

        await #expect(processExitsWith: .success) { [kind = kind as StoreKind, path = path as String] in
            let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
            let opened = try! kind.open(at: path, events: [Tapped.self])
            let store = opened.store
            var reports = store.dropReports.makeAsyncIterator()
            _ = store.append(EventRecord(event: Tapped(number: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location))
            let written = store.byteCount
            opened.failWrites()
            let expected = DropReport.writeFailed(recordCount: 1, timestamps: Date(timeIntervalSince1970: 2)...Date(timeIntervalSince1970: 2))

            let actual = store.append(EventRecord(event: Tapped(number: 2), timestamp: Date(timeIntervalSince1970: 2), sourceLocation: location))

            guard actual.deliveryTag == nil, await reports.next() == expected, store.byteCount == written, store.pendingRecordCount == 1 else {
                exit(1)
            }
        }
        let next = try kind.open(at: path, events: [Tapped.self]).store
        #expect(next.takeRecoveredRecords().compactMap { ($0.event as? Tapped)?.number } == [1])
    }

    @Test("A batch whose delivery mark can't be written is held back, never sent unmarked, and delivered on the next launch", arguments: StoreKind.all)
    func markFails(kind: StoreKind) async throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let destination = InMemoryDestination()
        let expected = [Tapped(number: 1), Tapped(number: 2)]

        await #expect(processExitsWith: .success) { [kind = kind as StoreKind, path = path as String] in
            let opened = try! kind.open(at: path, events: [Tapped.self])
            let store = opened.store
            let tracker = Tracker(store: store)
            let destination = InMemoryDestination()
            tracker.track(Tapped(number: 1))
            tracker.track(Tapped(number: 2))
            await tracker.finish()
            opened.failWrites()

            try? await tracker.records.batch(strategy: .count(2)).deliver(to: destination).execute()

            guard destination.batches.isEmpty, store.pendingRecordCount == 2 else {
                exit(1)
            }
        }
        let store = try kind.open(at: path, events: [Tapped.self]).store
        let tracker = Tracker(store: store)
        await tracker.finish()
        try await tracker.records.batch(strategy: .count(10)).deliver(to: destination).execute()

        #expect(destination.events(of: Tapped.self) == expected)
        #expect(destination.records.map(\.isRedelivered) == [false, false])
        #expect(store.byteCount == 0)
    }
}

extension RecordStoreWriteFailureExitTests.Tapped: BinaryCodable {
    func encode(to encoder: inout BinaryEncoder) {
        encoder.encode(number)
    }

    init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
        number = try decoder.decode()
    }
}
