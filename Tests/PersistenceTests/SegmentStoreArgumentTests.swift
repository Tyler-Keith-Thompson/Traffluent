import Events
import Foundation
import Persistence
import SystemPackage
import Testing

@Suite("SegmentStore: arguments and segment numbers", .timeLimit(.minutes(1)))
struct SegmentStoreArgumentTests {
    struct Tapped: Event, Equatable {
        var number: Int
    }

    enum Renamed: Event {
        static let name = "Tapped"

        case only
    }

    @Test("A bound of 8 bytes, no more than a segment's header, throws byteBoundTooSmall", arguments: [8, 0, -1, Int.min])
    func boundTooSmall(byteBound: Int) {
        let directory = FilePath(NSTemporaryDirectory()).appending("SegmentStoreArgumentTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }

        #expect(throws: SegmentStoreError.byteBoundTooSmall) {
            _ = try SegmentStore(events: [Tapped.self], directory: directory, byteBound: byteBound)
        }
    }

    @Test("A bound of 9 bytes, one past the header, is accepted")
    func boundPastHeader() throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("SegmentStoreArgumentTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let expected = 0

        let sut = try SegmentStore(events: [Tapped.self], directory: directory, byteBound: 9)

        #expect(sut.byteCount == expected)
    }

    @Test("A segment size of zero or less throws nonPositiveSegmentByteCount", arguments: [0, -1, Int.min])
    func segmentSizeNotPositive(segmentByteCount: Int) {
        let directory = FilePath(NSTemporaryDirectory()).appending("SegmentStoreArgumentTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }

        #expect(throws: SegmentStoreError.nonPositiveSegmentByteCount) {
            _ = try SegmentStore(events: [Tapped.self], directory: directory, segmentByteCount: segmentByteCount)
        }
    }

    @Test("A segment size of 1 byte is accepted")
    func smallestSegmentSize() throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("SegmentStoreArgumentTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let expected = 0

        let sut = try SegmentStore(events: [Tapped.self], directory: directory, segmentByteCount: 1)

        #expect(sut.pendingRecordCount == expected)
    }

    @Test("Two event types under one name throw duplicateEventName, and create no directory")
    func duplicateNames() {
        let directory = FilePath(NSTemporaryDirectory()).appending("SegmentStoreArgumentTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }

        #expect(throws: SegmentStoreError.duplicateEventName) {
            _ = try SegmentStore(events: [Tapped.self, Renamed.self], directory: directory)
        }
        #expect(!FileManager.default.fileExists(atPath: directory.string))
    }

    @Test("One event type listed twice is one type, and accepted")
    func repeatedType() throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("SegmentStoreArgumentTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        let sut = try SegmentStore(events: [Tapped.self, Tapped.self], directory: directory)

        let actual = sut.append(EventRecord(event: Tapped(number: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location))

        #expect(actual.deliveryTag != nil)
    }

    @Test("Once the log has used every segment number, a record that needs a new segment is kept in memory only and reported as a failed write")
    func segmentNumbersExhausted() async throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("SegmentStoreArgumentTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        let timestamp = Date(timeIntervalSince1970: 7)
        do {
            let earlier = try SegmentStore(events: [Tapped.self], directory: directory)
            _ = earlier.append(EventRecord(event: Tapped(number: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location))
        }
        // The last number a segment can have: 2³² - 1.
        try FileManager.default.moveItem(
            atPath: directory.appending("00000000000000000001.segment").string,
            toPath: directory.appending("00000000004294967295.segment").string
        )
        let sut = try SegmentStore(events: [Tapped.self], directory: directory)
        let expectedReport = DropReport.writeFailed(recordCount: 1, timestamps: timestamp...timestamp)

        let actual = sut.append(EventRecord(event: Tapped(number: 2), timestamp: timestamp, sourceLocation: location))

        var reports = sut.dropReports.makeAsyncIterator()
        #expect(actual.deliveryTag == nil)
        #expect(sut.pendingRecordCount == 1)
        #expect(await reports.next() == expectedReport)
    }

    @Test("A file numbered past every segment's number is not a segment: the store neither reads nor deletes it")
    func numberPastSegments() throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("SegmentStoreArgumentTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        do {
            let earlier = try SegmentStore(events: [Tapped.self], directory: directory)
            _ = earlier.append(EventRecord(event: Tapped(number: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location))
        }
        // 2³², one past the last number a segment can have.
        let past = directory.appending("00000000004294967296.segment")
        try FileManager.default.moveItem(atPath: directory.appending("00000000000000000001.segment").string, toPath: past.string)

        let sut = try SegmentStore(events: [Tapped.self], directory: directory)

        #expect(sut.pendingRecordCount == 0)
        #expect(FileManager.default.fileExists(atPath: past.string))
    }
}

extension SegmentStoreArgumentTests.Tapped: Codable {}

extension SegmentStoreArgumentTests.Renamed: Codable {
    private enum CodingKeys: CodingKey {}

    func encode(to encoder: any Encoder) throws {
        _ = encoder.container(keyedBy: CodingKeys.self)
    }

    init(from decoder: any Decoder) throws {
        _ = try decoder.container(keyedBy: CodingKeys.self)
        self = .only
    }
}
