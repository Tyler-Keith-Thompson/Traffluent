// Exit tests, in a file of their own: each runs its body in a child process, which some platforms
// (WASI) cannot start, and those builds leave out every file holding one.
//
// Each child lowers its file-size limit (RLIMIT_FSIZE), ignoring the SIGXFSZ that would end it,
// so every write that would grow a file past the limit fails with EFBIG, as a full disk fails
// it: a real failure, from the operating system, with no seam in the store. The limit is the
// process's alone, so it can't reach the other tests. A child exits 0 only if the store did what
// the test names; the parent then opens the directory as the next launch would.

import DestinationTesting
import Destinations
import Events
import Foundation
import Persistence
import SystemPackage
import Testing
import Trackers

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

@Suite("SegmentStore: write failures", .timeLimit(.minutes(1)))
struct SegmentStoreWriteFailureExitTests {
    struct Tapped: Event, Equatable {
        var number: Int
    }

    @Test("A record whose write fails is kept in memory only and reported, and the part written is cut off")
    func appendFails() async throws {
        let path: String = FilePath(NSTemporaryDirectory()).appending("SegmentStoreWriteFailureExitTests-\(UUID().uuidString)").string
        defer { try? FileManager.default.removeItem(atPath: path) }

        await #expect(processExitsWith: .success) { [path = path as String] in
            let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
            let store = try! SegmentStore(events: [Tapped.self], directory: FilePath(path))
            var reports = store.dropReports.makeAsyncIterator()
            _ = store.append(EventRecord(event: Tapped(number: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location))
            let written = store.byteCount
            // Room for 5 bytes of the next frame: the write fails partway.
            signal(SIGXFSZ, SIG_IGN)
            var limit = rlimit()
            #if canImport(Glibc)
            getrlimit(__rlimit_resource_t(RLIMIT_FSIZE.rawValue), &limit)
            limit.rlim_cur = rlim_t(written + 5)
            setrlimit(__rlimit_resource_t(RLIMIT_FSIZE.rawValue), &limit)
            #else
            getrlimit(RLIMIT_FSIZE, &limit)
            limit.rlim_cur = rlim_t(written + 5)
            setrlimit(RLIMIT_FSIZE, &limit)
            #endif
            let expected = DropReport.writeFailed(recordCount: 1, timestamps: Date(timeIntervalSince1970: 2)...Date(timeIntervalSince1970: 2))

            let actual = store.append(EventRecord(event: Tapped(number: 2), timestamp: Date(timeIntervalSince1970: 2), sourceLocation: location))

            let size = (try? FileManager.default.attributesOfItem(atPath: path + "/00000000000000000001.segment"))?[.size] as? Int
            guard actual.deliveryTag == nil, await reports.next() == expected, store.byteCount == written, size == written, store.pendingRecordCount == 1 else {
                exit(1)
            }
        }
        let next = try SegmentStore(events: [Tapped.self], directory: FilePath(path))
        #expect(next.takeRecoveredRecords().compactMap { ($0.event as? Tapped)?.number } == [1])
    }

    @Test("A record whose segment can't be created is kept in memory only and reported, and no part of the segment is left")
    func segmentFails() async throws {
        let path: String = FilePath(NSTemporaryDirectory()).appending("SegmentStoreWriteFailureExitTests-\(UUID().uuidString)").string
        defer { try? FileManager.default.removeItem(atPath: path) }

        await #expect(processExitsWith: .success) { [path = path as String] in
            let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
            let store = try! SegmentStore(events: [Tapped.self], directory: FilePath(path))
            var reports = store.dropReports.makeAsyncIterator()
            // Room for half a segment's header.
            signal(SIGXFSZ, SIG_IGN)
            var limit = rlimit()
            #if canImport(Glibc)
            getrlimit(__rlimit_resource_t(RLIMIT_FSIZE.rawValue), &limit)
            limit.rlim_cur = 4
            setrlimit(__rlimit_resource_t(RLIMIT_FSIZE.rawValue), &limit)
            #else
            getrlimit(RLIMIT_FSIZE, &limit)
            limit.rlim_cur = 4
            setrlimit(RLIMIT_FSIZE, &limit)
            #endif
            let expected = DropReport.writeFailed(recordCount: 1, timestamps: Date(timeIntervalSince1970: 1)...Date(timeIntervalSince1970: 1))

            let actual = store.append(EventRecord(event: Tapped(number: 1), timestamp: Date(timeIntervalSince1970: 1), sourceLocation: location))

            let files = try? FileManager.default.contentsOfDirectory(atPath: path)
            guard actual.deliveryTag == nil, await reports.next() == expected, store.byteCount == 0, files == [] else {
                exit(1)
            }
        }
    }

    @Test("A batch whose delivery mark can't be written is held back, never sent unmarked, and delivered on the next launch")
    func markFails() async throws {
        let path: String = FilePath(NSTemporaryDirectory()).appending("SegmentStoreWriteFailureExitTests-\(UUID().uuidString)").string
        defer { try? FileManager.default.removeItem(atPath: path) }
        let destination = InMemoryDestination()
        let expected = [Tapped(number: 1), Tapped(number: 2)]

        await #expect(processExitsWith: .success) { [path = path as String] in
            let store = try! SegmentStore(events: [Tapped.self], directory: FilePath(path))
            let tracker = Tracker(store: store)
            let destination = InMemoryDestination()
            tracker.track(Tapped(number: 1))
            tracker.track(Tapped(number: 2))
            tracker.finish()
            // No room for the mark.
            signal(SIGXFSZ, SIG_IGN)
            var limit = rlimit()
            #if canImport(Glibc)
            getrlimit(__rlimit_resource_t(RLIMIT_FSIZE.rawValue), &limit)
            limit.rlim_cur = rlim_t(store.byteCount)
            setrlimit(__rlimit_resource_t(RLIMIT_FSIZE.rawValue), &limit)
            #else
            getrlimit(RLIMIT_FSIZE, &limit)
            limit.rlim_cur = rlim_t(store.byteCount)
            setrlimit(RLIMIT_FSIZE, &limit)
            #endif

            try? await tracker.records.batch(strategy: .count(2)).deliver(to: destination).execute()

            guard destination.batches.isEmpty, store.pendingRecordCount == 2 else {
                exit(1)
            }
        }
        let store = try SegmentStore(events: [Tapped.self], directory: FilePath(path))
        let tracker = Tracker(store: store)
        tracker.finish()
        try await tracker.records.batch(strategy: .count(10)).deliver(to: destination).execute()

        #expect(destination.events(of: Tapped.self) == expected)
        #expect(destination.records.map(\.isRedelivered) == [false, false])
        #expect(store.byteCount == 0)
    }
}

extension SegmentStoreWriteFailureExitTests.Tapped: BinaryCodable {
    func encode(to encoder: inout BinaryEncoder) {
        encoder.encode(number)
    }

    init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
        number = try decoder.decode()
    }
}
