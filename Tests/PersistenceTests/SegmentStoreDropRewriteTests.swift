import Events
import Foundation
import Persistence
import SystemPackage
import Testing

// Recovery rewrites a segment it drops records from but keeps, so the drop is reported on one
// launch only. Each test writes a segment through one store, then opens later stores on the
// directory with event types that can't read some of its records. A store's drop reports end when
// it is gone, so a test reads them after letting it go.

@Suite("SegmentStore: rewriting a segment without its dropped records", .timeLimit(.minutes(1)))
struct SegmentStoreDropRewriteTests {
    struct Tapped: Event, Equatable {
        static let name = "Tapped"
        var number: Int
    }

    struct Other: Event {
        static let name = "Other"
    }

    /// `Other` with its version raised.
    struct OtherVersion2: Event {
        static let name = "Other"
        static let schemaVersion = 2
    }

    @Test("An undecodable record beside a pending one is reported on the first launch only; the pending one is recovered on both, not redelivered")
    func undecodableReportedOnce() async throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("SegmentStoreDropRewriteTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        do {
            let earlier = try SegmentStore(events: [Tapped.self, Other.self], directory: directory)
            _ = earlier.append(EventRecord(event: Other(), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location))
            _ = earlier.append(EventRecord(event: Tapped(number: 1), timestamp: Date(timeIntervalSince1970: 1), sourceLocation: location))
        }
        let expectedFirstReports: [DropReport] = [.undecodable(recordCount: 1)]
        let expectedSecondReports: [DropReport] = []
        let expectedNumbers = [1]
        let expectedRedelivered = [false]

        var firstReports = try SegmentStore(events: [Tapped.self], directory: directory).dropReports.makeAsyncIterator()
        var actualFirstReports: [DropReport] = []
        while let report = await firstReports.next() { actualFirstReports.append(report) }
        var secondReports: AsyncStream<DropReport>.AsyncIterator
        let actualNumbers: [Int]
        let actualRedelivered: [Bool]
        do {
            let sut = try SegmentStore(events: [Tapped.self], directory: directory)
            secondReports = sut.dropReports.makeAsyncIterator()
            let recovered = sut.takeRecoveredRecords()
            actualNumbers = recovered.compactMap { ($0.event as? Tapped)?.number }
            actualRedelivered = recovered.map(\.isRedelivered)
        }
        var actualSecondReports: [DropReport] = []
        while let report = await secondReports.next() { actualSecondReports.append(report) }

        #expect(actualFirstReports == expectedFirstReports)
        #expect(actualSecondReports == expectedSecondReports)
        #expect(actualNumbers == expectedNumbers)
        #expect(actualRedelivered == expectedRedelivered)
    }

    @Test("A record stored at another version beside a pending one is reported on the first launch only; the pending one is recovered on both")
    func versionMismatchReportedOnce() async throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("SegmentStoreDropRewriteTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        do {
            let earlier = try SegmentStore(events: [Tapped.self, Other.self], directory: directory)
            _ = earlier.append(EventRecord(event: Tapped(number: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location))
            _ = earlier.append(EventRecord(event: Other(), timestamp: Date(timeIntervalSince1970: 1), sourceLocation: location))
        }
        let expectedFirstReports: [DropReport] = [.versionMismatch(event: "Other", storedVersion: 1, currentVersion: 2, recordCount: 1)]
        let expectedSecondReports: [DropReport] = []
        let expectedNumbers = [1]
        let expectedRedelivered = [false]

        var firstReports = try SegmentStore(events: [Tapped.self, OtherVersion2.self], directory: directory).dropReports.makeAsyncIterator()
        var actualFirstReports: [DropReport] = []
        while let report = await firstReports.next() { actualFirstReports.append(report) }
        var secondReports: AsyncStream<DropReport>.AsyncIterator
        let actualNumbers: [Int]
        let actualRedelivered: [Bool]
        do {
            let sut = try SegmentStore(events: [Tapped.self, OtherVersion2.self], directory: directory)
            secondReports = sut.dropReports.makeAsyncIterator()
            let recovered = sut.takeRecoveredRecords()
            actualNumbers = recovered.compactMap { ($0.event as? Tapped)?.number }
            actualRedelivered = recovered.map(\.isRedelivered)
        }
        var actualSecondReports: [DropReport] = []
        while let report = await secondReports.next() { actualSecondReports.append(report) }

        #expect(actualFirstReports == expectedFirstReports)
        #expect(actualSecondReports == expectedSecondReports)
        #expect(actualNumbers == expectedNumbers)
        #expect(actualRedelivered == expectedRedelivered)
    }

    @Test("The rewrite keeps each record's delivery mark: one a delivery had started on is redelivered, one it hadn't is not")
    func deliveryMarksKept() async throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("SegmentStoreDropRewriteTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        do {
            let earlier = try SegmentStore(events: [Tapped.self, Other.self], directory: directory)
            _ = earlier.append(EventRecord(event: Other(), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location))
            let first = try #require(earlier.append(EventRecord(event: Tapped(number: 1), timestamp: Date(timeIntervalSince1970: 1), sourceLocation: location)).deliveryTag)
            _ = earlier.append(EventRecord(event: Tapped(number: 2), timestamp: Date(timeIntervalSince1970: 2), sourceLocation: location))
            let third = try #require(earlier.append(EventRecord(event: Tapped(number: 3), timestamp: Date(timeIntervalSince1970: 3), sourceLocation: location)).deliveryTag)
            _ = first.acknowledger.willDeliver([first.position, third.position])
        }
        let expectedNumbers = [1, 2, 3]
        let expectedRedelivered = [true, false, true]
        do {
            let first = try SegmentStore(events: [Tapped.self], directory: directory)
            #expect(first.takeRecoveredRecords().map(\.isRedelivered) == expectedRedelivered)
        }

        let sut = try SegmentStore(events: [Tapped.self], directory: directory)

        let recovered = sut.takeRecoveredRecords()
        let actualNumbers = recovered.compactMap { ($0.event as? Tapped)?.number }
        let actualRedelivered = recovered.map(\.isRedelivered)
        #expect(actualNumbers == expectedNumbers)
        #expect(actualRedelivered == expectedRedelivered)
    }

    @Test("A rewritten segment takes the launch's delivery marks and acknowledgements: a record marked comes back redelivered, and acknowledging every record deletes it")
    func rewrittenSegmentInUse() async throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("SegmentStoreDropRewriteTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        do {
            let earlier = try SegmentStore(events: [Tapped.self, Other.self], directory: directory)
            _ = earlier.append(EventRecord(event: Other(), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location))
            _ = earlier.append(EventRecord(event: Tapped(number: 1), timestamp: Date(timeIntervalSince1970: 1), sourceLocation: location))
            _ = earlier.append(EventRecord(event: Tapped(number: 2), timestamp: Date(timeIntervalSince1970: 2), sourceLocation: location))
        }
        let expectedRedelivered = [false, true]
        do {
            let first = try SegmentStore(events: [Tapped.self], directory: directory)
            let size = try FileManager.default.attributesOfItem(atPath: directory.appending("00000000000000000001.segment").string)[.size] as? Int
            #expect(first.byteCount == size)
            let tag = try #require(first.takeRecoveredRecords().last?.deliveryTag)
            #expect(tag.acknowledger.willDeliver([tag.position]).isEmpty)
        }

        let sut = try SegmentStore(events: [Tapped.self], directory: directory)

        let recovered = sut.takeRecoveredRecords()
        #expect(recovered.map(\.isRedelivered) == expectedRedelivered)
        let tags = recovered.compactMap(\.deliveryTag)
        #expect(tags.count == 2)
        tags.first?.acknowledger.acknowledge(tags.map(\.position))
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.string).isEmpty)
        #expect(sut.byteCount == 0)
    }

    @Test("A segment holding only records stored at another version is deleted on the first launch, rewritten never")
    func onlyVersionMismatched() async throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("SegmentStoreDropRewriteTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        do {
            let earlier = try SegmentStore(events: [Other.self], directory: directory)
            _ = earlier.append(EventRecord(event: Other(), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location))
        }
        let expected = DropReport.versionMismatch(event: "Other", storedVersion: 1, currentVersion: 2, recordCount: 1)

        let sut = try SegmentStore(events: [OtherVersion2.self], directory: directory)

        var reports = sut.dropReports.makeAsyncIterator()
        #expect(await reports.next() == expected)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.string).isEmpty)
        #expect(sut.byteCount == 0)
    }

    @Test("When the rewrite fails, the segment is recovered as it was, and the next launch reports its drop again")
    func failedRewrite() async throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("SegmentStoreDropRewriteTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        do {
            let earlier = try SegmentStore(events: [Tapped.self, Other.self], directory: directory)
            _ = earlier.append(EventRecord(event: Other(), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location))
            _ = earlier.append(EventRecord(event: Tapped(number: 1), timestamp: Date(timeIntervalSince1970: 1), sourceLocation: location))
        }
        // A directory where the rewritten file would go: creating the file fails, and so does
        // deleting it as an interrupted rewrite.
        let blocker = directory.appending("00000000000000000001.segment.rewriting")
        try FileManager.default.createDirectory(atPath: blocker.string, withIntermediateDirectories: false)
        let expectedReports: [DropReport] = [.undecodable(recordCount: 1)]
        let expectedNumbers = [1]
        var firstReports = try SegmentStore(events: [Tapped.self], directory: directory).dropReports.makeAsyncIterator()
        var actualFirstReports: [DropReport] = []
        while let report = await firstReports.next() { actualFirstReports.append(report) }

        var secondReports: AsyncStream<DropReport>.AsyncIterator
        let actualNumbers: [Int]
        do {
            let sut = try SegmentStore(events: [Tapped.self], directory: directory)
            secondReports = sut.dropReports.makeAsyncIterator()
            let recovered = sut.takeRecoveredRecords()
            actualNumbers = recovered.compactMap { ($0.event as? Tapped)?.number }
            // The kept record's position still names it in the old file: acknowledging it
            // deletes the segment.
            let tag = try #require(recovered.first?.deliveryTag)
            tag.acknowledger.acknowledge([tag.position])
            #expect(sut.pendingRecordCount == 0)
        }
        var actualSecondReports: [DropReport] = []
        while let report = await secondReports.next() { actualSecondReports.append(report) }

        #expect(actualFirstReports == expectedReports)
        #expect(actualSecondReports == expectedReports)
        #expect(actualNumbers == expectedNumbers)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.string) == ["00000000000000000001.segment.rewriting"])
    }

    @Test("A rewritten segment the bound evicts in the same launch reports its records with the times they were tracked")
    func rewrittenSegmentEvicted() async throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("SegmentStoreDropRewriteTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        do {
            let earlier = try SegmentStore(events: [Tapped.self, Other.self], directory: directory)
            _ = earlier.append(EventRecord(event: Other(), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location))
            _ = earlier.append(EventRecord(event: Tapped(number: 1), timestamp: Date(timeIntervalSince1970: 5), sourceLocation: location))
            _ = earlier.append(EventRecord(event: Tapped(number: 2), timestamp: Date(timeIntervalSince1970: 7), sourceLocation: location))
        }
        let expected: [DropReport] = [
            .undecodable(recordCount: 1),
            .sizeBound(recordCount: 2, timestamps: Date(timeIntervalSince1970: 5)...Date(timeIntervalSince1970: 7)),
        ]

        var reports = try SegmentStore(events: [Tapped.self], directory: directory, byteBound: 9).dropReports.makeAsyncIterator()

        var actual: [DropReport] = []
        while let report = await reports.next() { actual.append(report) }
        #expect(actual == expected)
    }

    @Test("A rewritten file a crash left before its rename is deleted at recovery")
    func interruptedRewriteDeleted() async throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("SegmentStoreDropRewriteTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        do {
            let earlier = try SegmentStore(events: [Tapped.self], directory: directory)
            _ = earlier.append(EventRecord(event: Tapped(number: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location))
        }
        // One of a segment numbered 7, which isn't there, and so isn't rewritten this launch.
        let leftover = directory.appending("00000000000000000007.segment.rewriting")
        try Data([0x54, 0x52]).write(to: URL(fileURLWithPath: leftover.string))
        let expected = ["00000000000000000001.segment"]

        let sut = try SegmentStore(events: [Tapped.self], directory: directory)

        let actual = try FileManager.default.contentsOfDirectory(atPath: directory.string)
        #expect(actual == expected)
        #expect(sut.takeRecoveredRecords().compactMap { ($0.event as? Tapped)?.number } == [1])
    }
}

extension SegmentStoreDropRewriteTests.Tapped: BinaryCodable {
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

extension SegmentStoreDropRewriteTests.Other: BinaryCodable {
    func encode(to encoder: inout BinaryEncoder) {
        encoder.encodeMap { _ in }
    }

    init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
        _ = try decoder.decodeMap()
    }
}

extension SegmentStoreDropRewriteTests.OtherVersion2: BinaryCodable {
    func encode(to encoder: inout BinaryEncoder) {
        encoder.encodeMap { _ in }
    }

    init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
        _ = try decoder.decodeMap()
    }
}
