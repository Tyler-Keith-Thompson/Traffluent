import Events
import Foundation
import Persistence
import SystemPackage
import Testing

// Every record here has the same frame size: the same event type, number width, call site and
// name. Each test measures it with a probe store, then sets its bound in frames.

@Suite("SegmentStore: byte bound", .timeLimit(.minutes(1)))
struct SegmentStoreBoundTests {
    struct Tapped: Event, Equatable {
        var number: Int
    }

    @Test("The default bound is 5 MiB")
    func defaultBound() {
        let expected = 5_242_880

        let actual = SegmentStore.defaultByteBound

        #expect(actual == expected)
    }

    @Test("A log filled exactly to its bound drops nothing; the next record drops the oldest segment and reports it")
    func exactlyFull() async throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("SegmentStoreBoundTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        func record(_ number: Int) -> EventRecord {
            EventRecord(event: Tapped(number: number), timestamp: Date(timeIntervalSince1970: Double(number)), sourceLocation: location)
        }
        let probe = try SegmentStore(events: [Tapped.self], directory: directory.appending("probe"))
        _ = probe.append(record(0))
        let segment = probe.byteCount
        let bound = 3 * segment
        let sut = try SegmentStore(events: [Tapped.self], directory: directory.appending("log"), byteBound: bound, segmentByteCount: segment)
        var reports = sut.dropReports.makeAsyncIterator()
        let expected = DropReport.sizeBound(recordCount: 1, timestamps: Date(timeIntervalSince1970: 0)...Date(timeIntervalSince1970: 0))

        for number in 0..<3 {
            _ = sut.append(record(number))
        }

        #expect(sut.byteCount == bound)
        #expect(sut.pendingRecordCount == 3)

        let fourth = sut.append(record(3))

        #expect(fourth.deliveryTag != nil)
        #expect(sut.byteCount == bound)
        #expect(sut.pendingRecordCount == 3)
        #expect(await reports.next() == expected)
        let next = try SegmentStore(events: [Tapped.self], directory: directory.appending("log"), byteBound: bound, segmentByteCount: segment)
        #expect(next.takeRecoveredRecords().compactMap { ($0.event as? Tapped)?.number } == [1, 2, 3])
    }

    @Test("A bound one byte short of three segments holds only two")
    func oneByteShort() async throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("SegmentStoreBoundTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        func record(_ number: Int) -> EventRecord {
            EventRecord(event: Tapped(number: number), timestamp: Date(timeIntervalSince1970: Double(number)), sourceLocation: location)
        }
        let probe = try SegmentStore(events: [Tapped.self], directory: directory.appending("probe"))
        _ = probe.append(record(0))
        let segment = probe.byteCount
        let bound = 3 * segment - 1
        let sut = try SegmentStore(events: [Tapped.self], directory: directory.appending("log"), byteBound: bound, segmentByteCount: segment)
        var reports = sut.dropReports.makeAsyncIterator()
        let expected = DropReport.sizeBound(recordCount: 1, timestamps: Date(timeIntervalSince1970: 0)...Date(timeIntervalSince1970: 0))

        for number in 0..<3 {
            _ = sut.append(record(number))
        }

        #expect(sut.byteCount == 2 * segment)
        #expect(sut.pendingRecordCount == 2)
        #expect(await reports.next() == expected)
    }

    @Test("A record exactly the size an empty log can hold is kept")
    func largestRecord() throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("SegmentStoreBoundTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let record = EventRecord(event: Tapped(number: 0), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1))
        let probe = try SegmentStore(events: [Tapped.self], directory: directory.appending("probe"))
        _ = probe.append(record)
        let bound = probe.byteCount
        let sut = try SegmentStore(events: [Tapped.self], directory: directory.appending("log"), byteBound: bound)

        let actual = sut.append(record)

        #expect(actual.deliveryTag != nil)
        #expect(sut.byteCount == bound)
    }

    @Test("A drop report counts only the dropped segment's records not yet delivered, over their timestamps")
    func reportCountsPending() async throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("SegmentStoreBoundTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        func record(_ number: Int, at seconds: Double) -> EventRecord {
            EventRecord(event: Tapped(number: number), timestamp: Date(timeIntervalSince1970: seconds), sourceLocation: location)
        }
        let probe = try SegmentStore(events: [Tapped.self], directory: directory.appending("probe"))
        _ = probe.append(record(0, at: 0))
        let frame = probe.byteCount - 8
        let segment = 8 + 4 * frame
        let sut = try SegmentStore(events: [Tapped.self], directory: directory.appending("log"), byteBound: 2 * segment, segmentByteCount: segment)
        var reports = sut.dropReports.makeAsyncIterator()
        let expected = DropReport.sizeBound(recordCount: 3, timestamps: Date(timeIntervalSince1970: 10)...Date(timeIntervalSince1970: 50))
        let first = [record(0, at: 30), record(1, at: 5), record(2, at: 50), record(3, at: 10)].map(sut.append)
        let delivered = try #require(first[1].deliveryTag)
        delivered.acknowledger.acknowledge([delivered.position])
        for number in 4..<8 {
            _ = sut.append(record(number, at: 100))
        }

        _ = sut.append(record(8, at: 200))

        #expect(await reports.next() == expected)
        #expect(sut.byteCount <= 2 * segment)
    }

    @Test("A delivery mark that would pass the bound drops the oldest segment first, and reports it")
    func markWithinBound() async throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("SegmentStoreBoundTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        func record(_ number: Int) -> EventRecord {
            EventRecord(event: Tapped(number: number), timestamp: Date(timeIntervalSince1970: Double(number)), sourceLocation: location)
        }
        let probe = try SegmentStore(events: [Tapped.self], directory: directory.appending("probe"))
        _ = probe.append(record(0))
        let segment = probe.byteCount
        let log = directory.appending("log")
        let sut = try SegmentStore(events: [Tapped.self], directory: log, byteBound: 2 * segment, segmentByteCount: segment)
        var reports = sut.dropReports.makeAsyncIterator()
        let expected = DropReport.sizeBound(recordCount: 1, timestamps: Date(timeIntervalSince1970: 0)...Date(timeIntervalSince1970: 0))
        _ = sut.append(record(0))
        let tag = try #require(sut.append(record(1)).deliveryTag)

        _ = tag.acknowledger.willDeliver([tag.position])

        #expect(await reports.next() == expected)
        #expect(sut.byteCount <= 2 * segment)
        let next = try SegmentStore(events: [Tapped.self], directory: log)
        let recovered = next.takeRecoveredRecords()
        #expect(recovered.compactMap { ($0.event as? Tapped)?.number } == [1])
        #expect(recovered.map(\.isRedelivered) == [true])
    }

    #if canImport(Darwin)
    // The immutable flag, which a file's owner may set on Apple platforms (Linux's needs root),
    // makes deleting a segment fail while new ones can still be created.
    @Test("A segment whose file can't be deleted still counts toward the bound, and a record that would pass it is kept in memory and reported")
    func undeletableSegment() async throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("SegmentStoreBoundTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        func record(_ number: Int) -> EventRecord {
            EventRecord(event: Tapped(number: number), timestamp: Date(timeIntervalSince1970: Double(number)), sourceLocation: location)
        }
        let probe = try SegmentStore(events: [Tapped.self], directory: directory.appending("probe"))
        _ = probe.append(record(0))
        let segment = probe.byteCount
        let log = directory.appending("log")
        let sut = try SegmentStore(events: [Tapped.self], directory: log, byteBound: 2 * segment, segmentByteCount: segment)
        let tag = try #require(sut.append(record(1)).deliveryTag)
        _ = sut.append(record(2))
        let names = try FileManager.default.contentsOfDirectory(atPath: log.string)
        for name in names {
            try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: log.appending(name).string)
        }
        defer {
            for name in names {
                try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: log.appending(name).string)
            }
        }
        var reports = sut.dropReports.makeAsyncIterator()
        let expected: [DropReport] = [
            .sizeBound(recordCount: 1, timestamps: Date(timeIntervalSince1970: 1)...Date(timeIntervalSince1970: 1)),
            .sizeBound(recordCount: 1, timestamps: Date(timeIntervalSince1970: 2)...Date(timeIntervalSince1970: 2)),
            .writeFailed(recordCount: 1, timestamps: Date(timeIntervalSince1970: 3)...Date(timeIntervalSince1970: 3)),
        ]

        let actual = sut.append(record(3))

        let onDisk = try FileManager.default.contentsOfDirectory(atPath: log.string).map { name in
            try FileManager.default.attributesOfItem(atPath: log.appending(name).string)[.size] as? Int ?? 0
        }.reduce(0, +)
        #expect(onDisk == 2 * segment)
        #expect(sut.byteCount == onDisk)
        #expect(actual.deliveryTag == nil)
        #expect(await [reports.next(), reports.next(), reports.next()] == expected)
        // Its records, still on disk, come back on the next launch: they can't go out unmarked.
        #expect(tag.acknowledger.willDeliver([tag.position]) == [tag.position])
    }
    #endif

    @Test("A segment's size is an eighth of the bound unless given")
    func defaultSegmentSize() throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("SegmentStoreBoundTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        let record = EventRecord(event: Tapped(number: 0), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location)
        let probe = try SegmentStore(events: [Tapped.self], directory: directory.appending("probe"))
        _ = probe.append(record)
        let frame = probe.byteCount - 8
        // Room for exactly two frames per segment.
        let sut = try SegmentStore(events: [Tapped.self], directory: directory.appending("log"), byteBound: 8 * (8 + 2 * frame))

        for _ in 0..<5 {
            _ = sut.append(record)
        }

        let files = try FileManager.default.contentsOfDirectory(atPath: directory.appending("log").string)
        #expect(files.count == 3)
    }

}

extension SegmentStoreBoundTests.Tapped: BinaryCodable {
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
