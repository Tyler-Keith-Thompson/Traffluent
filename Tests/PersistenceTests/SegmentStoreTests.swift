import Checksums
import Events
import Foundation
import Persistence
import SystemPackage
import Testing

@Suite("SegmentStore", .timeLimit(.minutes(1)))
struct SegmentStoreTests {
    struct Tapped: Event, Equatable {
        var number: Int
    }

    @Test("A segment is deleted only once every record in it is acknowledged")
    func deletedWhole() throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("SegmentStoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let sut = try SegmentStore(events: [Tapped.self], directory: directory)
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        let records = (0..<3).map { sut.append(EventRecord(event: Tapped(number: $0), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location)) }
        let tags = try records.map { try #require($0.deliveryTag) }
        let fullSize = sut.byteCount

        tags[0].acknowledger.acknowledge([tags[0].position, tags[1].position])

        #expect(sut.pendingRecordCount == 1)
        #expect(sut.byteCount == fullSize)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.string).count == 1)

        tags[2].acknowledger.acknowledge([tags[2].position])

        #expect(sut.pendingRecordCount == 0)
        #expect(sut.byteCount == 0)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.string).isEmpty)
    }

    @Test("Acknowledging records of two segments in interleaved order deletes both")
    func interleavedAcknowledgement() throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("SegmentStoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        func record(_ number: Int) -> EventRecord {
            EventRecord(event: Tapped(number: number), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location)
        }
        let probe = try SegmentStore(events: [Tapped.self], directory: directory.appending("probe"))
        _ = probe.append(record(0))
        let frame = probe.byteCount - 8
        let log = directory.appending("log")
        let sut = try SegmentStore(events: [Tapped.self], directory: log, segmentByteCount: 8 + 2 * frame)
        let tags = try (0..<4).map { try #require(sut.append(record($0)).deliveryTag) }

        tags[0].acknowledger.acknowledge([tags[0].position, tags[2].position, tags[1].position, tags[3].position])

        #expect(sut.pendingRecordCount == 0)
        #expect(try FileManager.default.contentsOfDirectory(atPath: log.string).isEmpty)
    }

    @Test("After the active segment is delivered and deleted, the next record starts a new one")
    func newSegmentAfterDeletion() async throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("SegmentStoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let sut = try SegmentStore(events: [Tapped.self], directory: directory)
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        let first = try #require(sut.append(EventRecord(event: Tapped(number: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location)).deliveryTag)
        first.acknowledger.acknowledge([first.position])

        let second = sut.append(EventRecord(event: Tapped(number: 2), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location))

        #expect(second.deliveryTag != nil)
        #expect(sut.pendingRecordCount == 1)
        let next = try SegmentStore(events: [Tapped.self], directory: directory)
        #expect(next.takeRecoveredRecords().compactMap { $0.event as? Tapped } == [Tapped(number: 2)])
    }

    @Test("Marking records across two segments, without acknowledging them, brings them back redelivered; the others not")
    func willDeliverMarks() throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("SegmentStoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        let probe = try SegmentStore(events: [Tapped.self], directory: directory.appending("probe"))
        _ = probe.append(EventRecord(event: Tapped(number: 0), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location))
        let frame = probe.byteCount - 8
        let log = directory.appending("log")
        let sut = try SegmentStore(events: [Tapped.self], directory: log, segmentByteCount: 8 + 2 * frame)
        let tags = try (0..<4).map { number in
            try #require(sut.append(EventRecord(event: Tapped(number: number), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location)).deliveryTag)
        }

        _ = tags[0].acknowledger.willDeliver([tags[1].position, tags[2].position])

        let next = try SegmentStore(events: [Tapped.self], directory: log)
        #expect(next.takeRecoveredRecords().map(\.isRedelivered) == [false, true, true, false])
    }

    @Test("A recovered record keeps the identifier it was stored with, redelivered or not")
    func recoveredIdentifiers() throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("SegmentStoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let sut = try SegmentStore(events: [Tapped.self], directory: directory)
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        let records = (0..<2).map { EventRecord(event: Tapped(number: $0), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location) }
        let expected = records.map(\.id)
        let expectedRedelivered = [true, false]
        let tags = try records.map { try #require(sut.append($0).deliveryTag) }
        _ = tags[0].acknowledger.willDeliver([tags[0].position])

        let actual = try SegmentStore(events: [Tapped.self], directory: directory).takeRecoveredRecords()

        #expect(actual.map(\.id) == expected)
        #expect(actual.map(\.isRedelivered) == expectedRedelivered)
    }

    @Test("A segment is the TRFL header, version 2, then frames of length, CRC-32 and payload, a record's payload a CBOR map starting with its identifier")
    func format() throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("SegmentStoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let sut = try SegmentStore(events: [Tapped.self], directory: directory)
        let expectedHeader: [UInt8] = [0x54, 0x52, 0x46, 0x4C, 2, 0, 0, 0]
        // A map of six entries, the first "id": a 16-byte byte string tagged 37.
        let expectedMapStart: [UInt8] = [0xA6, 0x62, 0x69, 0x64, 0xD8, 0x25, 0x50]
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)

        let record = EventRecord(event: Tapped(number: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location)
        let expectedIdentifier = withUnsafeBytes(of: record.id.uuid) { Array($0) }

        _ = sut.append(record)

        let name = try #require(try FileManager.default.contentsOfDirectory(atPath: directory.string).first)
        let bytes = try #require(FileManager.default.contents(atPath: directory.appending(name).string)).map { $0 }
        #expect(name == "00000000000000000001.segment")
        #expect(Array(bytes[0..<8]) == expectedHeader)
        let length = bytes[8..<12].reversed().reduce(0) { $0 << 8 | Int($1) }
        let checksum = bytes[12..<16].reversed().reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        let payload = Array(bytes[16...])
        #expect(length == payload.count)
        #expect(checksum == payload.withUnsafeBytes { CRC32.checksum(of: $0) })
        #expect(payload.first == 0)
        #expect(Array(payload[1..<8]) == expectedMapStart)
        #expect(Array(payload[8..<24]) == expectedIdentifier)
        #expect(sut.byteCount == bytes.count)
    }

    @Test("A store creates its directory and any missing parents")
    func createsDirectory() throws {
        let root = FilePath(NSTemporaryDirectory()).appending("SegmentStoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: root.string) }
        let directory = root.appending("a").appending("b")
        var isDirectory: ObjCBool = false

        let sut = try SegmentStore(events: [Tapped.self], directory: directory)

        #expect(sut.directory == directory)
        #expect(FileManager.default.fileExists(atPath: directory.string, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
    }

    @Test("A store whose directory can't be created throws")
    func uncreatableDirectory() throws {
        let root = FilePath(NSTemporaryDirectory()).appending("SegmentStoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: root.string) }
        try FileManager.default.createDirectory(atPath: root.string, withIntermediateDirectories: true)
        let file = root.appending("file")
        try #require(FileManager.default.createFile(atPath: file.string, contents: Data([1])))

        #expect(throws: Errno.self) {
            _ = try SegmentStore(events: [Tapped.self], directory: file.appending("log"))
        }
    }

    @Test("Files in the directory that aren't segments are left alone")
    func otherFiles() throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("SegmentStoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        try FileManager.default.createDirectory(atPath: directory.string, withIntermediateDirectories: true)
        let expected = ["00000000000000000001.journal", "1.segment", "notes.txt"]
        for name in expected {
            try #require(FileManager.default.createFile(atPath: directory.appending(name).string, contents: Data([1, 2, 3])))
        }

        let sut = try SegmentStore(events: [Tapped.self], directory: directory)

        #expect(sut.takeRecoveredRecords().isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.string).sorted() == expected)
    }

    #if canImport(Darwin)
    @Test("By default a store lives under Application Support, in a directory of the app's own named Traffluent")
    func defaultDirectory() {
        let expectedParent = FilePath(URL.applicationSupportDirectory.path(percentEncoded: false))

        let actual = SegmentStore.defaultDirectory

        #expect(actual.starts(with: expectedParent))
        #expect(actual.lastComponent?.string == "Traffluent")
        #expect(actual.components.count == expectedParent.components.count + 2)
    }

    @Test("A store's directory is excluded from backups")
    func excludedFromBackup() throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("SegmentStoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }

        _ = try SegmentStore(events: [Tapped.self], directory: directory)

        let values = try URL(fileURLWithPath: directory.string).resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }
    #else
    @Test("By default a store lives in the XDG state directory, under the process's name, in traffluent")
    func defaultDirectory() {
        let environment = ProcessInfo.processInfo.environment
        let state = environment["XDG_STATE_HOME"].map({ FilePath($0) }).flatMap { $0.isAbsolute ? $0 : nil }
            ?? FilePath(environment["HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.path).appending(".local").appending("state")
        let expected = state.appending(ProcessInfo.processInfo.processName).appending("traffluent")

        let actual = SegmentStore.defaultDirectory

        #expect(actual == expected)
    }
    #endif
}

extension SegmentStoreTests.Tapped: BinaryCodable {
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
