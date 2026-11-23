import Checksums
import DestinationTesting
import Destinations
import Events
import Foundation
import Persistence
import SystemPackage
import Testing
import Trackers

@Suite("SegmentStore", .timeLimit(.minutes(1)))
struct SegmentStoreTests {
    struct Tapped: Event, Equatable {
        var number: Int
    }

    struct Untracked: Event {
        var number: Int
    }

    @Test("track writes the record to the log before it returns, and a store opened next on the directory recovers it")
    func writeThrough() throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("SegmentStoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let store = try SegmentStore(events: [Tapped.self], directory: directory)
        let tracker = Tracker(store: store)
        let expected = [Tapped(number: 1)]

        tracker.track(Tapped(number: 1))

        #expect(store.pendingRecordCount == 1)
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.string).filter { $0.hasSuffix(".segment") }
        #expect(files.count == 1)
        let next = try SegmentStore(events: [Tapped.self], directory: directory)
        let recovered = next.takeRecoveredRecords()
        #expect(recovered.compactMap { $0.event as? Tapped } == expected)
        #expect(recovered.map(\.isRedelivered) == [false])
    }

    @Test("A recovered record keeps its timestamp and source location, in the top-level context")
    func recoveredFields() throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("SegmentStoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let expectedTimestamp = Date(timeIntervalSinceReferenceDate: 12_345.678)
        let expectedLocation = Events.SourceLocation(file: "/src/App/Checkout.swift", fileID: "App/Checkout.swift", function: "pay(for:)", line: 42, column: 7)
        let store = try SegmentStore(events: [Tapped.self], directory: directory)

        _ = store.append(EventRecord(event: Tapped(number: 3), timestamp: expectedTimestamp, sourceLocation: expectedLocation))

        let next = try SegmentStore(events: [Tapped.self], directory: directory)
        let actual = try #require(next.takeRecoveredRecords().first)
        #expect(actual.timestamp == expectedTimestamp)
        #expect(actual.sourceLocation == expectedLocation)
        #expect(actual.context.isEmpty)
        #expect(actual.name == "Tapped")
    }

    @Test("A recovered record whose file equals its fileID keeps both")
    func recoveredFileEqualToFileID() throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("SegmentStoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let expectedLocation = Events.SourceLocation(file: "App/Checkout.swift", fileID: "App/Checkout.swift", function: "pay(for:)", line: 1, column: 1)
        let store = try SegmentStore(events: [Tapped.self], directory: directory)

        _ = store.append(EventRecord(event: Tapped(number: 3), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: expectedLocation))

        let next = try SegmentStore(events: [Tapped.self], directory: directory)
        let actual = try #require(next.takeRecoveredRecords().first)
        #expect(actual.sourceLocation == expectedLocation)
    }

    @Test("Recovered records are handed out once: a second take returns none")
    func takeOnce() throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("SegmentStoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let first = try SegmentStore(events: [Tapped.self], directory: directory)
        _ = first.append(EventRecord(event: Tapped(number: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)))
        let sut = try SegmentStore(events: [Tapped.self], directory: directory)

        let taken = sut.takeRecoveredRecords()
        let actual = sut.takeRecoveredRecords()

        #expect(taken.count == 1)
        #expect(actual.isEmpty)
    }

    @Test("A tracker given a store delivers what earlier runs left first, then what it tracks")
    func recoveredFirst() async throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("SegmentStoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let earlier = Tracker(store: try SegmentStore(events: [Tapped.self], directory: directory))
        earlier.track(Tapped(number: 1))
        earlier.track(Tapped(number: 2))
        let destination = InMemoryDestination()
        let store = try SegmentStore(events: [Tapped.self], directory: directory)
        let sut = Tracker(store: store)
        let expected = [Tapped(number: 1), Tapped(number: 2), Tapped(number: 3)]

        sut.track(Tapped(number: 3))
        sut.finish()
        try await sut.records.batch(strategy: .count(10)).deliver(to: destination).execute()

        #expect(destination.events(of: Tapped.self) == expected)
        #expect(destination.records.map(\.isRedelivered) == [false, false, false])
    }

    @Test("Delivering every record leaves the log empty: no bytes, no records, no segment files")
    func emptyAfterDelivery() async throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("SegmentStoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let store = try SegmentStore(events: [Tapped.self], directory: directory, segmentByteCount: 200)
        let tracker = Tracker(store: store)
        let destination = InMemoryDestination()

        for number in 0..<25 {
            tracker.track(Tapped(number: number))
        }
        tracker.finish()
        try await tracker.records.batch(strategy: .count(10)).deliver(to: destination).execute()

        #expect(destination.records.count == 25)
        #expect(store.byteCount == 0)
        #expect(store.pendingRecordCount == 0)
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.string).filter { $0.hasSuffix(".segment") }
        #expect(files.isEmpty)
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

    @Test("Acknowledging a record twice, or a position the log never held, changes nothing")
    func repeatedAcknowledgement() throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("SegmentStoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let sut = try SegmentStore(events: [Tapped.self], directory: directory)
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        let records = (0..<2).map { sut.append(EventRecord(event: Tapped(number: $0), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location)) }
        let tag = try #require(records[0].deliveryTag)

        tag.acknowledger.acknowledge([tag.position])
        tag.acknowledger.acknowledge([tag.position, tag.position + 100, 99 << 32])

        #expect(sut.pendingRecordCount == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.string).count == 1)
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

    @Test("An event type not in the store's list stays in memory only: delivered in this run, never written, not recovered")
    func memoryOnly() async throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("SegmentStoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let store = try SegmentStore(events: [Tapped.self], directory: directory)
        let tracker = Tracker(store: store)
        let destination = InMemoryDestination()

        tracker.track(Untracked(number: 1))
        tracker.finish()

        #expect(store.byteCount == 0)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.string).isEmpty)
        try await tracker.records.batch(strategy: .count(10)).deliver(to: destination).execute()
        #expect(destination.events(of: Untracked.self).map(\.number) == [1])
        #expect(destination.records.map { $0.deliveryTag == nil } == [true])
        let next = try SegmentStore(events: [Tapped.self], directory: directory)
        #expect(next.takeRecoveredRecords().isEmpty)
    }

    @Test("An event type not in the store's list produces no drop report")
    func memoryOnlyNotReported() async throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("SegmentStoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        let probe = try SegmentStore(events: [Tapped.self], directory: directory.appending("probe"))
        _ = probe.append(EventRecord(event: Tapped(number: 0), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location))
        let frame = probe.byteCount - 8
        let sut = try SegmentStore(events: [Tapped.self], directory: directory.appending("log"), byteBound: 8 + frame)
        var reports = sut.dropReports.makeAsyncIterator()
        let expected = DropReport.sizeBound(recordCount: 1, timestamps: Date(timeIntervalSince1970: 1)...Date(timeIntervalSince1970: 1))

        _ = sut.append(EventRecord(event: Untracked(number: 0), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location))
        _ = sut.append(EventRecord(event: Tapped(number: 1), timestamp: Date(timeIntervalSince1970: 1), sourceLocation: location))
        _ = sut.append(EventRecord(event: Tapped(number: 2), timestamp: Date(timeIntervalSince1970: 2), sourceLocation: location))

        // The first report is the Tapped record the bound dropped: the untracked event made none.
        let actual = await reports.next()
        #expect(actual == expected)
    }

    @Test("A segment is the TRFL header, version 1, then frames of length, CRC-32 and payload")
    func format() throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("SegmentStoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let sut = try SegmentStore(events: [Tapped.self], directory: directory)
        let expectedHeader: [UInt8] = [0x54, 0x52, 0x46, 0x4C, 1, 0, 0, 0]
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)

        _ = sut.append(EventRecord(event: Tapped(number: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location))

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
        FileManager.default.createFile(atPath: file.string, contents: Data([1]))

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
            FileManager.default.createFile(atPath: directory.appending(name).string, contents: Data([1, 2, 3]))
        }

        let sut = try SegmentStore(events: [Tapped.self], directory: directory)

        #expect(sut.takeRecoveredRecords().isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.string).sorted() == expected)
    }

    @Test("Synchronizing keeps every record")
    func synchronize() throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("SegmentStoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let sut = try SegmentStore(events: [Tapped.self], directory: directory)
        let tracker = Tracker(store: sut)
        tracker.track(Tapped(number: 1))

        sut.synchronize()
        sut.synchronize()

        #expect(sut.pendingRecordCount == 1)
        let next = try SegmentStore(events: [Tapped.self], directory: directory)
        #expect(next.takeRecoveredRecords().count == 1)
    }

    @Test("An event tracked after finish isn't delivered in this run, but is written for the next")
    func trackedAfterFinish() async throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("SegmentStoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let tracker = Tracker(store: try SegmentStore(events: [Tapped.self], directory: directory))
        let destination = InMemoryDestination()

        tracker.finish()
        tracker.track(Tapped(number: 1))
        try await tracker.records.batch(strategy: .count(10)).deliver(to: destination).execute()

        #expect(destination.records.isEmpty)
        let next = try SegmentStore(events: [Tapped.self], directory: directory)
        #expect(next.takeRecoveredRecords().compactMap { $0.event as? Tapped } == [Tapped(number: 1)])
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
        encoder.encode(number)
    }

    init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
        number = try decoder.decode()
    }
}
