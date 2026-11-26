// An @Event struct whose declaration changed between releases, reading the records a store kept
// from the earlier one: each version is a struct of its own, under the same event name. A change
// that keeps the version reads the earlier records; one that raises it drops them, reporting both
// versions.

import CBOR
import EventMacros
import Foundation
import Persistence
import SwiftCBOR
import Testing

@Suite("@Event: schema changes", .timeLimit(.minutes(1)))
struct EventMacroSchemaChangeTests {
    @Event(name: "checkout_started")
    struct Original {
        var cartSize: Int
        var screen: String
    }

    @Event(name: "checkout_started")
    struct WithCoupon {
        var cartSize: Int
        var screen: String
        var coupon: String?
    }

    @Event(name: "checkout_started")
    struct WithoutScreen {
        var cartSize: Int
    }

    @Event(name: "checkout_started")
    struct WithCurrency {
        var cartSize: Int
        var screen: String
        var currency: String
    }

    @Event(name: "checkout_started")
    struct Retyped {
        var cartSize: Double
        var screen: String
    }

    /// Version 1 after compatible changes: an optional property and two with default values
    /// added, and `screen` removed.
    @Event(name: "checkout_started")
    struct Compatible {
        var cartSize: Int
        var coupon: String?
        var currency: String = "USD"
        var referrer: String? = "organic"
    }

    /// A breaking change, with the version raised: `cartSize` retyped.
    @Event(name: "checkout_started", version: 2)
    struct RetypedVersion2 {
        var cartSize: Double
        var screen: String
    }

    /// Version 1's shape, with the version raised for a change of meaning alone.
    @Event(name: "checkout_started", version: 2)
    struct SameShapeVersion2 {
        var cartSize: Int
        var screen: String
    }

    /// A segment holding a record without a version: one record of `Original`,
    /// with `cartSize` 3 and `screen` "Cart", tracked at the reference date with no call site.
    static let segmentWithoutVersions: [UInt8] = [
        0x54, 0x52, 0x46, 0x4C, 0x03, 0x00, 0x00, 0x00, 0x71, 0x00, 0x00, 0x00, 0xA3, 0x23, 0xD5, 0x5E,
        0x00, 0xA4, 0x62, 0x69, 0x64, 0x78, 0x24, 0x36, 0x46, 0x39, 0x36, 0x31, 0x39, 0x46, 0x46, 0x2D,
        0x38, 0x42, 0x38, 0x36, 0x2D, 0x44, 0x30, 0x31, 0x31, 0x2D, 0x42, 0x34, 0x32, 0x44, 0x2D, 0x30,
        0x30, 0x43, 0x30, 0x34, 0x46, 0x43, 0x39, 0x36, 0x34, 0x46, 0x46, 0x64, 0x6E, 0x61, 0x6D, 0x65,
        0x70, 0x63, 0x68, 0x65, 0x63, 0x6B, 0x6F, 0x75, 0x74, 0x5F, 0x73, 0x74, 0x61, 0x72, 0x74, 0x65,
        0x64, 0x65, 0x65, 0x76, 0x65, 0x6E, 0x74, 0xA2, 0x66, 0x73, 0x63, 0x72, 0x65, 0x65, 0x6E, 0x64,
        0x43, 0x61, 0x72, 0x74, 0x68, 0x63, 0x61, 0x72, 0x74, 0x53, 0x69, 0x7A, 0x65, 0x03, 0x69, 0x74,
        0x69, 0x6D, 0x65, 0x73, 0x74, 0x61, 0x6D, 0x70, 0xFB, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00,
    ]

    @Test("A record stored before an optional property was added decodes with it nil")
    func optionalAdded() throws {
        let directory = NSTemporaryDirectory() + "EventMacroSchemaChangeTests-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: directory) }
        do {
            let earlier = try SegmentStore(events: [Original.self], directory: .init(directory))
            _ = earlier.append(EventRecord(event: Original(cartSize: 3, screen: "Cart"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil))
        }

        let sut = try SegmentStore(events: [WithCoupon.self], directory: .init(directory))

        let actual = sut.takeRecoveredRecords().compactMap { $0.event as? WithCoupon }
        #expect(actual.map(\.cartSize) == [3])
        #expect(actual.map(\.screen) == ["Cart"])
        #expect(actual.map(\.coupon) == [nil])
    }

    @Test("A record stored before a property was removed decodes with the rest intact")
    func propertyRemoved() throws {
        let directory = NSTemporaryDirectory() + "EventMacroSchemaChangeTests-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: directory) }
        do {
            let earlier = try SegmentStore(events: [Original.self], directory: .init(directory))
            _ = earlier.append(EventRecord(event: Original(cartSize: 3, screen: "Cart"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil))
        }

        let sut = try SegmentStore(events: [WithoutScreen.self], directory: .init(directory))

        let actual = sut.takeRecoveredRecords().compactMap { $0.event as? WithoutScreen }
        #expect(actual.map(\.cartSize) == [3])
    }

    @Test("A record stored before a required property was added, or a property's type changed, is dropped and reported", arguments: [false, true])
    func undecodable(retyped: Bool) async throws {
        let directory = NSTemporaryDirectory() + "EventMacroSchemaChangeTests-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: directory) }
        do {
            let earlier = try SegmentStore(events: [Original.self], directory: .init(directory))
            _ = earlier.append(EventRecord(event: Original(cartSize: 3, screen: "Cart"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil))
        }
        let expected = DropReport.undecodable(recordCount: 1)

        let sut = try SegmentStore(events: [retyped ? Retyped.self : WithCurrency.self], directory: .init(directory))

        var reports = sut.dropReports.makeAsyncIterator()
        #expect(await reports.next() == expected)
        #expect(sut.takeRecoveredRecords().isEmpty)
    }

    @Test("An @Event encoding is the CBOR map another decoder reads, each property under its name, a nil left out")
    func independentDecoder() throws {
        let expected: SwiftCBOR.CBOR = .map([
            .utf8String("cartSize"): .unsignedInt(3),
            .utf8String("screen"): .utf8String("Cart"),
        ])
        let bytes = try CBOREncoder().encode(WithCoupon(cartSize: 3, screen: "Cart", coupon: nil))
        let actual = try SwiftCBOR.CBOR.decode(bytes)

        #expect(actual == expected)
    }

    @Test("A store relaunched over a record without a version reads it by name, through compatible changes")
    func segmentWithoutVersions() throws {
        let directory = NSTemporaryDirectory() + "EventMacroSchemaChangeTests-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: directory) }
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try Data(EventMacroSchemaChangeTests.segmentWithoutVersions).write(to: URL(fileURLWithPath: directory + "/00000000000000000001.segment"))
        let expectedID = UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")
        let expectedTimestamp = Date(timeIntervalSinceReferenceDate: 0)

        let sut = try SegmentStore(events: [Compatible.self], directory: .init(directory))

        let recovered = sut.takeRecoveredRecords()
        let actual = recovered.compactMap { $0.event as? Compatible }
        #expect(recovered.map(\.id) == [expectedID])
        #expect(recovered.map(\.timestamp) == [expectedTimestamp])
        #expect(actual.map(\.cartSize) == [3])
        #expect(actual.map(\.coupon) == [nil])
        #expect(actual.map(\.currency) == ["USD"])
        #expect(actual.map(\.referrer) == ["organic"])
    }

    @Test("A record without a version is read by a type at version 2 that reads its bytes, and dropped as undecodable by one that doesn't")
    func segmentWithoutVersionsRaised() async throws {
        let directory = NSTemporaryDirectory() + "EventMacroSchemaChangeTests-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: directory) }
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try Data(EventMacroSchemaChangeTests.segmentWithoutVersions).write(to: URL(fileURLWithPath: directory + "/00000000000000000001.segment"))
        let expectedReport = DropReport.undecodable(recordCount: 1)
        let expectedCartSizes = [3]
        do {
            let reading = try SegmentStore(events: [SameShapeVersion2.self], directory: .init(directory))
            let actual = reading.takeRecoveredRecords().compactMap { $0.event as? SameShapeVersion2 }
            #expect(actual.map(\.cartSize) == expectedCartSizes)
        }
        try FileManager.default.removeItem(atPath: directory)
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try Data(EventMacroSchemaChangeTests.segmentWithoutVersions).write(to: URL(fileURLWithPath: directory + "/00000000000000000001.segment"))

        let sut = try SegmentStore(events: [RetypedVersion2.self], directory: .init(directory))

        var reports = sut.dropReports.makeAsyncIterator()
        #expect(await reports.next() == expectedReport)
        #expect(sut.takeRecoveredRecords().isEmpty)
    }

    @Test("A record stored at version 1 reads after compatible changes that keep the version: an optional property nil, defaulted ones their defaults, a removed one skipped")
    func compatibleChanges() throws {
        let directory = NSTemporaryDirectory() + "EventMacroSchemaChangeTests-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: directory) }
        do {
            let earlier = try SegmentStore(events: [Original.self], directory: .init(directory))
            _ = earlier.append(EventRecord(event: Original(cartSize: 3, screen: "Cart"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil))
        }

        let sut = try SegmentStore(events: [Compatible.self], directory: .init(directory))

        let actual = sut.takeRecoveredRecords().compactMap { $0.event as? Compatible }
        #expect(actual.map(\.cartSize) == [3])
        #expect(actual.map(\.coupon) == [nil])
        #expect(actual.map(\.currency) == ["USD"])
        #expect(actual.map(\.referrer) == ["organic"])
    }

    @Test("A property with a default value reads its stored value when the record holds one, nil included, and its default only when the key is missing")
    func defaultValueOnlyWhenMissing() throws {
        let stored = Compatible(cartSize: 1, coupon: "SPRING", currency: "EUR", referrer: nil)
        let bytes = try CBOREncoder().encode(stored)

        let actual = try CBORDecoder().decode(Compatible.self, from: bytes)

        #expect(actual.currency == "EUR")
        #expect(actual.referrer == nil)
        #expect(actual.coupon == "SPRING")
    }

    @Test("A record stored at version 1 is dropped without being read once the version is raised, reported with the event and both versions", arguments: [false, true])
    func versionRaised(sameShape: Bool) async throws {
        let directory = NSTemporaryDirectory() + "EventMacroSchemaChangeTests-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: directory) }
        do {
            let earlier = try SegmentStore(events: [Original.self], directory: .init(directory))
            _ = earlier.append(EventRecord(event: Original(cartSize: 3, screen: "Cart"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil))
            _ = earlier.append(EventRecord(event: Original(cartSize: 4, screen: "Cart"), timestamp: Date(timeIntervalSince1970: 1), sourceLocation: nil))
        }
        let expected = DropReport.versionMismatch(event: "checkout_started", storedVersion: 1, currentVersion: 2, recordCount: 2)

        let sut = try SegmentStore(events: [sameShape ? SameShapeVersion2.self : RetypedVersion2.self], directory: .init(directory))

        var reports = sut.dropReports.makeAsyncIterator()
        #expect(await reports.next() == expected)
        #expect(sut.takeRecoveredRecords().isEmpty)
        #expect(sut.pendingRecordCount == 0)
    }

    @Test("A record stored at version 2 is dropped by a release whose type is at version 1, as after a rollback, reported with both versions")
    func versionLowered() async throws {
        let directory = NSTemporaryDirectory() + "EventMacroSchemaChangeTests-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: directory) }
        do {
            let later = try SegmentStore(events: [SameShapeVersion2.self], directory: .init(directory))
            _ = later.append(EventRecord(event: SameShapeVersion2(cartSize: 3, screen: "Cart"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil))
        }
        let expected = DropReport.versionMismatch(event: "checkout_started", storedVersion: 2, currentVersion: 1, recordCount: 1)

        let sut = try SegmentStore(events: [Original.self], directory: .init(directory))

        var reports = sut.dropReports.makeAsyncIterator()
        #expect(await reports.next() == expected)
        #expect(sut.takeRecoveredRecords().isEmpty)
    }

    @Test("A record stored at the type's raised version reads back")
    func sameRaisedVersion() throws {
        let directory = NSTemporaryDirectory() + "EventMacroSchemaChangeTests-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: directory) }
        do {
            let earlier = try SegmentStore(events: [RetypedVersion2.self], directory: .init(directory))
            _ = earlier.append(EventRecord(event: RetypedVersion2(cartSize: 2.5, screen: "Cart"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil))
        }

        let sut = try SegmentStore(events: [RetypedVersion2.self], directory: .init(directory))

        let actual = sut.takeRecoveredRecords().compactMap { $0.event as? RetypedVersion2 }
        #expect(actual.map(\.cartSize) == [2.5])
    }
}
