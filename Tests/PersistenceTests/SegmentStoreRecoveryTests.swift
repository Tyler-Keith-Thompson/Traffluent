import Checksums
import Events
import Foundation
import Persistence
import SystemPackage
import Testing

// Each test writes a segment through one store, damages the file as a crash, a power cut or a bad
// disk would, and opens the next store on the directory.

@Suite("SegmentStore: recovery", .timeLimit(.minutes(1)))
struct SegmentStoreRecoveryTests {
    struct Tapped: Event, Equatable {
        var number: Int
    }

    struct Other: Event {}

    @Test("A torn last record is cut off; every record before it is recovered, and the cut bytes are reported")
    func tornLastRecord() async throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("SegmentStoreRecoveryTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        let earlier = try SegmentStore(events: [Tapped.self], directory: directory)
        for number in 0..<3 {
            _ = earlier.append(EventRecord(event: Tapped(number: number), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location))
        }
        let frame = (earlier.byteCount - 8) / 3
        let path = directory.appending("00000000000000000001.segment")
        let bytes = try #require(FileManager.default.contents(atPath: path.string))
        try bytes.dropLast(3).write(to: URL(fileURLWithPath: path.string))
        let expected = DropReport.corruption(byteCount: frame - 3)

        let sut = try SegmentStore(events: [Tapped.self], directory: directory)

        var reports = sut.dropReports.makeAsyncIterator()
        #expect(await reports.next() == expected)
        #expect(sut.takeRecoveredRecords().compactMap { ($0.event as? Tapped)?.number } == [0, 1])
        #expect(try FileManager.default.attributesOfItem(atPath: path.string)[.size] as? Int == 8 + 2 * frame)
        #expect(sut.byteCount == 8 + 2 * frame)
    }

    @Test("A last record missing only its final byte is cut off")
    func tornByOneByte() async throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("SegmentStoreRecoveryTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        let earlier = try SegmentStore(events: [Tapped.self], directory: directory)
        for number in 0..<2 {
            _ = earlier.append(EventRecord(event: Tapped(number: number), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location))
        }
        let frame = (earlier.byteCount - 8) / 2
        let path = directory.appending("00000000000000000001.segment")
        let bytes = try #require(FileManager.default.contents(atPath: path.string))
        try bytes.dropLast(1).write(to: URL(fileURLWithPath: path.string))
        let expected = DropReport.corruption(byteCount: frame - 1)

        let sut = try SegmentStore(events: [Tapped.self], directory: directory)

        var reports = sut.dropReports.makeAsyncIterator()
        #expect(await reports.next() == expected)
        #expect(sut.takeRecoveredRecords().compactMap { ($0.event as? Tapped)?.number } == [0])
        #expect(sut.byteCount == 8 + frame)
    }

    @Test("A zero-filled tail, as a file system can leave after a crash, is cut off; the records before it are recovered")
    func zeroFilledTail() async throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("SegmentStoreRecoveryTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        let earlier = try SegmentStore(events: [Tapped.self], directory: directory)
        _ = earlier.append(EventRecord(event: Tapped(number: 0), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location))
        let written = earlier.byteCount
        let path = directory.appending("00000000000000000001.segment")
        let bytes = try #require(FileManager.default.contents(atPath: path.string))
        try (bytes + Data(count: 8)).write(to: URL(fileURLWithPath: path.string))
        let expected = DropReport.corruption(byteCount: 8)

        let sut = try SegmentStore(events: [Tapped.self], directory: directory)

        var reports = sut.dropReports.makeAsyncIterator()
        #expect(await reports.next() == expected)
        #expect(sut.takeRecoveredRecords().compactMap { ($0.event as? Tapped)?.number } == [0])
        #expect(sut.byteCount == written)
    }

    @Test("A corrupted byte in a middle record cuts the segment there: the records before it are recovered, the rest reported")
    func corruptMiddleByte() async throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("SegmentStoreRecoveryTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        let earlier = try SegmentStore(events: [Tapped.self], directory: directory)
        for number in 0..<3 {
            _ = earlier.append(EventRecord(event: Tapped(number: number), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location))
        }
        let frame = (earlier.byteCount - 8) / 3
        let path = directory.appending("00000000000000000001.segment")
        var bytes = try #require(FileManager.default.contents(atPath: path.string))
        bytes[8 + frame + frame / 2] ^= 0x40
        try bytes.write(to: URL(fileURLWithPath: path.string))
        let expected = DropReport.corruption(byteCount: 2 * frame)

        let sut = try SegmentStore(events: [Tapped.self], directory: directory)

        var reports = sut.dropReports.makeAsyncIterator()
        #expect(await reports.next() == expected)
        #expect(sut.takeRecoveredRecords().compactMap { ($0.event as? Tapped)?.number } == [0])
        #expect(try FileManager.default.attributesOfItem(atPath: path.string)[.size] as? Int == 8 + frame)
    }

    @Test("A corrupted checksum or length cuts the segment at that record")
    func corruptFrameHeader() async throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("SegmentStoreRecoveryTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        let earlier = try SegmentStore(events: [Tapped.self], directory: directory)
        for number in 0..<3 {
            _ = earlier.append(EventRecord(event: Tapped(number: number), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location))
        }
        let frame = (earlier.byteCount - 8) / 3
        let first = directory.appending("00000000000000000001.segment")
        let original = try #require(FileManager.default.contents(atPath: first.string))
        var checksum = original
        checksum[8 + frame + 4] ^= 0x01
        var length = original
        length[8 + 2 * frame + 3] = 0x7F
        try checksum.write(to: URL(fileURLWithPath: first.string))
        try length.write(to: URL(fileURLWithPath: directory.appending("00000000000000000002.segment").string))
        var zero = original
        zero.replaceSubrange(8 + frame..<8 + frame + 4, with: [0, 0, 0, 0])
        try zero.write(to: URL(fileURLWithPath: directory.appending("00000000000000000003.segment").string))
        let expected = [DropReport.corruption(byteCount: 2 * frame), .corruption(byteCount: frame), .corruption(byteCount: 2 * frame)]

        let sut = try SegmentStore(events: [Tapped.self], directory: directory)

        var reports = sut.dropReports.makeAsyncIterator()
        var actual: [DropReport] = []
        for _ in expected {
            actual.append(try #require(await reports.next()))
        }
        #expect(actual == expected)
        #expect(sut.takeRecoveredRecords().compactMap { ($0.event as? Tapped)?.number } == [0, 0, 1, 0])
    }

    @Test("A segment in a later version of the format, left by a newer release, is kept untouched, unread and outside the bound")
    func newerVersion() async throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("SegmentStoreRecoveryTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        try FileManager.default.createDirectory(atPath: directory.string, withIntermediateDirectories: true)
        let newer = directory.appending("00000000000000000001.segment")
        // Version 3, with a reserved byte set and bytes this version can't read.
        let expected = Data([0x54, 0x52, 0x46, 0x4C, 3, 0, 7, 0, 0xFF, 0xFF, 0xFF, 0xFF, 1, 2, 3])
        try expected.write(to: URL(fileURLWithPath: newer.string))

        let sut = try SegmentStore(events: [Tapped.self], directory: directory)
        // Its record goes in segment 2: the newer segment keeps its number.
        let tag = try #require(sut.append(EventRecord(event: Tapped(number: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location)).deliveryTag)
        tag.acknowledger.acknowledge([tag.position])

        #expect(sut.takeRecoveredRecords().isEmpty)
        #expect(sut.byteCount == 0)
        #expect(FileManager.default.contents(atPath: newer.string) == expected)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.string) == ["00000000000000000001.segment"])
    }

    @Test("A segment whose header has the wrong magic number, or names an earlier version than 2, version 1's records included, is discarded whole and reported")
    func unreadableHeader() async throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("SegmentStoreRecoveryTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        let earlier = try SegmentStore(events: [Tapped.self], directory: directory)
        _ = earlier.append(EventRecord(event: Tapped(number: 0), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location))
        let path = directory.appending("00000000000000000001.segment")
        var magic = try #require(FileManager.default.contents(atPath: path.string))
        var version = magic
        var first = magic
        magic[0] = 0x55
        version[4] = 0
        first[4] = 1
        try magic.write(to: URL(fileURLWithPath: path.string))
        try version.write(to: URL(fileURLWithPath: directory.appending("00000000000000000002.segment").string))
        try first.write(to: URL(fileURLWithPath: directory.appending("00000000000000000003.segment").string))
        let expected = [DropReport.corruption(byteCount: magic.count), .corruption(byteCount: version.count), .corruption(byteCount: first.count)]

        let sut = try SegmentStore(events: [Tapped.self], directory: directory)

        var reports = sut.dropReports.makeAsyncIterator()
        let actual = [try #require(await reports.next()), try #require(await reports.next()), try #require(await reports.next())]
        #expect(actual == expected)
        #expect(sut.takeRecoveredRecords().isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.string).isEmpty)
    }

    @Test("An empty segment, or a header with no records, is deleted without a report")
    func emptySegments() async throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("SegmentStoreRecoveryTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        try FileManager.default.createDirectory(atPath: directory.string, withIntermediateDirectories: true)
        try #require(FileManager.default.createFile(atPath: directory.appending("00000000000000000001.segment").string, contents: Data()))
        try #require(FileManager.default.createFile(atPath: directory.appending("00000000000000000002.segment").string, contents: Data([0x54, 0x52, 0x46, 0x4C, 2, 0, 0, 0])))
        // A short third segment, the only one recovery reports.
        try #require(FileManager.default.createFile(atPath: directory.appending("00000000000000000003.segment").string, contents: Data([0x54, 0x52, 0x46])))
        let expected = DropReport.corruption(byteCount: 3)

        let sut = try SegmentStore(events: [Tapped.self], directory: directory)

        var reports = sut.dropReports.makeAsyncIterator()
        #expect(await reports.next() == expected)
        #expect(sut.takeRecoveredRecords().isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.string).isEmpty)
        #expect(sut.byteCount == 0)
    }

    @Test("A frame of a kind this version doesn't know cuts the segment there, even with a valid checksum")
    func unknownKind() async throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("SegmentStoreRecoveryTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        let earlier = try SegmentStore(events: [Tapped.self], directory: directory)
        _ = earlier.append(EventRecord(event: Tapped(number: 0), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location))
        let path = directory.appending("00000000000000000001.segment")
        let payload: [UInt8] = [7, 1, 2]
        let checksum = payload.withUnsafeBytes { CRC32.checksum(of: $0) }
        let frame: [UInt8] = [3, 0, 0, 0] + withUnsafeBytes(of: checksum.littleEndian) { Array($0) } + payload
        var bytes = try #require(FileManager.default.contents(atPath: path.string))
        bytes.append(contentsOf: frame)
        try bytes.write(to: URL(fileURLWithPath: path.string))
        let expected = DropReport.corruption(byteCount: frame.count)

        let sut = try SegmentStore(events: [Tapped.self], directory: directory)

        var reports = sut.dropReports.makeAsyncIterator()
        #expect(await reports.next() == expected)
        #expect(sut.takeRecoveredRecords().compactMap { ($0.event as? Tapped)?.number } == [0])
    }

    @Test("A delivery mark whose length isn't whole record numbers cuts the segment there")
    func malformedMark() async throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("SegmentStoreRecoveryTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        let earlier = try SegmentStore(events: [Tapped.self], directory: directory)
        _ = earlier.append(EventRecord(event: Tapped(number: 0), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location))
        let path = directory.appending("00000000000000000001.segment")
        let payload: [UInt8] = [1, 0, 0, 0]
        let checksum = payload.withUnsafeBytes { CRC32.checksum(of: $0) }
        let frame: [UInt8] = [4, 0, 0, 0] + withUnsafeBytes(of: checksum.littleEndian) { Array($0) } + payload
        var bytes = try #require(FileManager.default.contents(atPath: path.string))
        bytes.append(contentsOf: frame)
        try bytes.write(to: URL(fileURLWithPath: path.string))
        let expected = DropReport.corruption(byteCount: frame.count)

        let sut = try SegmentStore(events: [Tapped.self], directory: directory)

        var reports = sut.dropReports.makeAsyncIterator()
        #expect(await reports.next() == expected)
        #expect(sut.takeRecoveredRecords().map(\.isRedelivered) == [false])
    }

    @Test("Intact records of an event type the store doesn't list are dropped and reported as undecodable")
    func undecodable() async throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("SegmentStoreRecoveryTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        let earlier = try SegmentStore(events: [Tapped.self, Other.self], directory: directory)
        _ = earlier.append(EventRecord(event: Other(), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location))
        _ = earlier.append(EventRecord(event: Tapped(number: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location))
        _ = earlier.append(EventRecord(event: Other(), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location))
        let expected = DropReport.undecodable(recordCount: 2)

        let sut = try SegmentStore(events: [Tapped.self], directory: directory)

        var reports = sut.dropReports.makeAsyncIterator()
        #expect(await reports.next() == expected)
        let recovered = sut.takeRecoveredRecords()
        #expect(recovered.compactMap { ($0.event as? Tapped)?.number } == [1])
        // The undecodable records count as delivered: acknowledging the one left deletes the segment.
        let tag = try #require(recovered.first?.deliveryTag)
        tag.acknowledger.acknowledge([tag.position])
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.string).isEmpty)
    }

    @Test("A record holding bytes past its map, in an intact frame, is undecodable")
    func trailingBytes() async throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("SegmentStoreRecoveryTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        let earlier = try SegmentStore(events: [Tapped.self], directory: directory)
        _ = earlier.append(EventRecord(event: Tapped(number: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location))
        let path = directory.appending("00000000000000000001.segment")
        let bytes = try #require(FileManager.default.contents(atPath: path.string)).map { $0 }
        // The record's frame again, its payload one byte longer, its length and checksum to match.
        let payload = Array(bytes[16...]) + [0x00]
        let length = UInt32(payload.count)
        let checksum = payload.withUnsafeBytes { CRC32.checksum(of: $0) }
        let frame = (0 ..< 4).map { UInt8(truncatingIfNeeded: length >> (8 * $0)) } + (0 ..< 4).map { UInt8(truncatingIfNeeded: checksum >> (8 * $0)) } + payload
        try Data(Array(bytes[0 ..< 8]) + frame).write(to: URL(fileURLWithPath: path.string))
        let expected = DropReport.undecodable(recordCount: 1)

        let sut = try SegmentStore(events: [Tapped.self], directory: directory)

        var reports = sut.dropReports.makeAsyncIterator()
        #expect(await reports.next() == expected)
        #expect(sut.takeRecoveredRecords().isEmpty)
    }

    @Test("A segment holding only undecodable records is deleted at recovery")
    func onlyUndecodable() async throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("SegmentStoreRecoveryTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        let earlier = try SegmentStore(events: [Other.self], directory: directory)
        _ = earlier.append(EventRecord(event: Other(), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location))
        let expected = DropReport.undecodable(recordCount: 1)

        let sut = try SegmentStore(events: [Tapped.self], directory: directory)

        var reports = sut.dropReports.makeAsyncIterator()
        #expect(await reports.next() == expected)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.string).isEmpty)
        #expect(sut.byteCount == 0)
    }

    @Test("Segments are recovered oldest first, and new records go to a segment numbered after them")
    func order() throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("SegmentStoreRecoveryTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        let probe = try SegmentStore(events: [Tapped.self], directory: directory.appending("probe"))
        _ = probe.append(EventRecord(event: Tapped(number: 0), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location))
        let segment = probe.byteCount
        let log = directory.appending("log")
        let earlier = try SegmentStore(events: [Tapped.self], directory: log, segmentByteCount: segment)
        for number in 0..<12 {
            _ = earlier.append(EventRecord(event: Tapped(number: number), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location))
        }
        let expected = Array(0..<12)

        let sut = try SegmentStore(events: [Tapped.self], directory: log, segmentByteCount: segment)
        _ = sut.append(EventRecord(event: Tapped(number: 12), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location))

        #expect(sut.takeRecoveredRecords().compactMap { ($0.event as? Tapped)?.number } == expected)
        #expect(try FileManager.default.contentsOfDirectory(atPath: log.string).sorted().last == "00000000000000000013.segment")
    }
}

extension SegmentStoreRecoveryTests.Tapped: BinaryCodable {
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

extension SegmentStoreRecoveryTests.Other: BinaryCodable {
    func encode(to encoder: inout BinaryEncoder) {
        encoder.encodeMap { _ in }
    }

    init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
        _ = try decoder.decodeMap()
    }
}
