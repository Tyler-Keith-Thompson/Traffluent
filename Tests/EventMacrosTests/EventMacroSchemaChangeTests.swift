// An @Event struct whose declaration changed between releases, reading the records a store kept
// from the earlier one: each version is a struct of its own, under the same event name.

import EventMacros
import Foundation
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

    @Test("An @Event encoding is the CBOR map another decoder reads, each property under its name")
    func independentDecoder() throws {
        let expected: CBOR = .map([
            .utf8String("cartSize"): .unsignedInt(3),
            .utf8String("screen"): .utf8String("Cart"),
            .utf8String("coupon"): .null,
        ])
        var encoder = BinaryEncoder()

        WithCoupon(cartSize: 3, screen: "Cart", coupon: nil).encode(to: &encoder)
        let actual = try CBOR.decode(encoder.bytes)

        #expect(actual == expected)
    }
}
