import Events
import Foundation
import Persistence
import Testing

// Each record is stored with its event's schemaVersion: one at the type's version is read, one at
// another is dropped unread and reported with both versions, and one without a version is read by
// its name at whatever version the type is, and dropped as undecodable when it doesn't read.

@Suite("Records: schema versions", .timeLimit(.minutes(1)))
struct RecordVersionTests {
    struct CheckoutStarted: Event, Equatable {
        static let name = "checkout_started"
        var cartSize: Int
        var screen: String
    }

    struct CheckoutStartedVersion2: Event, Equatable {
        static let name = "checkout_started"
        static let schemaVersion = 2
        var cartSize: Int
        var screen: String
    }

    struct CheckoutStartedRetypedVersion2: Event, Equatable {
        static let name = "checkout_started"
        static let schemaVersion = 2
        var cartSize: Int
        var screen: Int
    }

    /// A segment holding a record without a version: one record of
    /// `CheckoutStarted`, with `cartSize` 3 and `screen` "Cart", tracked at the reference date with
    /// no call site.
    static let segmentWithoutVersions: [UInt8] = [
        0x54, 0x52, 0x46, 0x4C, 0x02, 0x00, 0x00, 0x00, 0x6E, 0x00, 0x00, 0x00, 0x60, 0x0D, 0x81, 0x17,
        0x00, 0xA5, 0x62, 0x69, 0x64, 0xD8, 0x25, 0x50, 0x6F, 0x96, 0x19, 0xFF, 0x8B, 0x86, 0xD0, 0x11,
        0xB4, 0x2D, 0x00, 0xC0, 0x4F, 0xC9, 0x64, 0xFF, 0x69, 0x74, 0x69, 0x6D, 0x65, 0x73, 0x74, 0x61,
        0x6D, 0x70, 0xFB, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x64, 0x6E, 0x61, 0x6D, 0x65,
        0x70, 0x63, 0x68, 0x65, 0x63, 0x6B, 0x6F, 0x75, 0x74, 0x5F, 0x73, 0x74, 0x61, 0x72, 0x74, 0x65,
        0x64, 0x6E, 0x73, 0x6F, 0x75, 0x72, 0x63, 0x65, 0x4C, 0x6F, 0x63, 0x61, 0x74, 0x69, 0x6F, 0x6E,
        0xF6, 0x65, 0x65, 0x76, 0x65, 0x6E, 0x74, 0xA2, 0x68, 0x63, 0x61, 0x72, 0x74, 0x53, 0x69, 0x7A,
        0x65, 0x03, 0x66, 0x73, 0x63, 0x72, 0x65, 0x65, 0x6E, 0x64, 0x43, 0x61, 0x72, 0x74,
    ]

    @Test("A record without a version is read by its name: a type at version 1 reads it")
    func withoutVersionIsVersion1() throws {
        let directory = NSTemporaryDirectory() + "RecordVersionTests-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: directory) }
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try Data(RecordVersionTests.segmentWithoutVersions).write(to: URL(fileURLWithPath: directory + "/00000000000000000001.segment"))
        let expected = [CheckoutStarted(cartSize: 3, screen: "Cart")]

        let sut = try SegmentStore(events: [CheckoutStarted.self], directory: .init(directory))

        let actual = sut.takeRecoveredRecords().compactMap { $0.event as? CheckoutStarted }
        #expect(actual == expected)
    }

    @Test("A record without a version has no version to compare: a type at version 2 that reads its bytes reads it")
    func withoutVersionRaisedReads() throws {
        let directory = NSTemporaryDirectory() + "RecordVersionTests-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: directory) }
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try Data(RecordVersionTests.segmentWithoutVersions).write(to: URL(fileURLWithPath: directory + "/00000000000000000001.segment"))
        let expected = [CheckoutStartedVersion2(cartSize: 3, screen: "Cart")]

        let sut = try SegmentStore(events: [CheckoutStartedVersion2.self], directory: .init(directory))

        let actual = sut.takeRecoveredRecords().compactMap { $0.event as? CheckoutStartedVersion2 }
        #expect(actual == expected)
    }

    @Test("A record without a version that its type at version 2 can't read is dropped as undecodable, not as a version mismatch")
    func withoutVersionUndecodable() async throws {
        let directory = NSTemporaryDirectory() + "RecordVersionTests-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: directory) }
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try Data(RecordVersionTests.segmentWithoutVersions).write(to: URL(fileURLWithPath: directory + "/00000000000000000001.segment"))
        let expected = DropReport.undecodable(recordCount: 1)

        let sut = try SegmentStore(events: [CheckoutStartedRetypedVersion2.self], directory: .init(directory))

        var reports = sut.dropReports.makeAsyncIterator()
        #expect(await reports.next() == expected)
        #expect(sut.takeRecoveredRecords().isEmpty)
    }

    @Test("A record stored at a type's raised version reads back at that version", arguments: StoreKind.all)
    func raisedVersionRoundTrip(kind: StoreKind) throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        do {
            let earlier = try kind.open(at: path, events: [CheckoutStartedVersion2.self]).store
            _ = earlier.append(EventRecord(event: CheckoutStartedVersion2(cartSize: 3, screen: "Cart"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil))
        }
        let expected = [CheckoutStartedVersion2(cartSize: 3, screen: "Cart")]

        let sut = try kind.open(at: path, events: [CheckoutStartedVersion2.self]).store

        let actual = sut.takeRecoveredRecords().compactMap { $0.event as? CheckoutStartedVersion2 }
        #expect(actual == expected)
    }

    @Test("Mismatched records are counted per event, stored and current version, and reported by the event's name's bytes, then the stored version")
    func mismatchCountsOrder() {
        var sut = VersionMismatchCounts()
        let expected: [DropReport] = [
            .versionMismatch(event: "Swiped", storedVersion: 4, currentVersion: 2, recordCount: 1),
            .versionMismatch(event: "Tapped", storedVersion: 1, currentVersion: 2, recordCount: 2),
            .versionMismatch(event: "Tapped", storedVersion: 3, currentVersion: 2, recordCount: 1),
            .versionMismatch(event: "swiped", storedVersion: 1, currentVersion: 2, recordCount: 1),
        ]

        sut.add(event: "Tapped", storedVersion: 3, currentVersion: 2)
        sut.add(event: "swiped", storedVersion: 1, currentVersion: 2)
        sut.add(event: "Tapped", storedVersion: 1, currentVersion: 2)
        sut.add(event: "Swiped", storedVersion: 4, currentVersion: 2)
        sut.add(event: "Tapped", storedVersion: 1, currentVersion: 2)
        let actual = sut.reports

        #expect(actual == expected)
    }

    @Test("No mismatched records make no reports")
    func noMismatches() {
        let sut = VersionMismatchCounts()

        let actual = sut.reports

        #expect(actual.isEmpty)
    }
}

extension RecordVersionTests.CheckoutStarted: BinaryCodable {
    func encode(to encoder: inout BinaryEncoder) {
        encoder.encodeMap { map in
            map.encode(cartSize, forKey: "cartSize")
            map.encode(screen, forKey: "screen")
        }
    }

    init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
        var map = try decoder.decodeMap()
        cartSize = try map.decode(forKey: "cartSize")
        screen = try map.decode(forKey: "screen")
    }
}

extension RecordVersionTests.CheckoutStartedVersion2: BinaryCodable {
    func encode(to encoder: inout BinaryEncoder) {
        encoder.encodeMap { map in
            map.encode(cartSize, forKey: "cartSize")
            map.encode(screen, forKey: "screen")
        }
    }

    init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
        var map = try decoder.decodeMap()
        cartSize = try map.decode(forKey: "cartSize")
        screen = try map.decode(forKey: "screen")
    }
}

extension RecordVersionTests.CheckoutStartedRetypedVersion2: BinaryCodable {
    func encode(to encoder: inout BinaryEncoder) {
        encoder.encodeMap { map in
            map.encode(cartSize, forKey: "cartSize")
            map.encode(screen, forKey: "screen")
        }
    }

    init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
        var map = try decoder.decodeMap()
        cartSize = try map.decode(forKey: "cartSize")
        screen = try map.decode(forKey: "screen")
    }
}
