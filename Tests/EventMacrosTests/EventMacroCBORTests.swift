// What @Event's conformance writes through the CBOR package a store uses, pinned byte for byte and
// read back by an independent decoder (SwiftCBOR), so a mistake in the expansion can't hide behind
// the same mistake in the package's decoder. Both modules name a type CBOR: SwiftCBOR's is always
// written SwiftCBOR.CBOR here, and CBOREncoder is the package's alone.

import CBOR
import EventMacros
import Foundation
import Persistence
import PropertyBased
import SwiftCBOR
import Testing
import TraffluentTestSupport

@Suite("@Event: CBOR")
struct EventMacroCBORTests {
    struct Address: Codable, Sendable, Equatable {
        var city: String
    }

    @Event
    struct Ordered: Equatable {
        var at: Date
        var order: UUID
        var email: Sensitive<String>
        var coupon: String?
        var items: [Int]
        var shipTo: Address
    }

    @Test("A store's encoding writes each property under its name: a Date as the double of its seconds since 2001, a UUID as its string, a sensitive value as itself, a nested value as a map, an array as an array, an optional's nil left out")
    func revealed() throws {
        let order = try #require(UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF"))
        let event = Ordered(at: Date(timeIntervalSinceReferenceDate: 0.5), order: order, email: Sensitive("a@b.c"), coupon: nil, items: [1, 2], shipTo: Address(city: "Oslo"))
        // {"at": 0.5, "email": "a@b.c", "items": [1, 2], "order": "6F96…", "shipTo": {"city": "Oslo"}},
        // keys in CBOR's sorted order: shorter first, then bytewise.
        let expectedBytes: [UInt8] = [
            0xA5,
            0x62, 0x61, 0x74, 0xFB, 0x3F, 0xE0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x65, 0x65, 0x6D, 0x61, 0x69, 0x6C, 0x65, 0x61, 0x40, 0x62, 0x2E, 0x63,
            0x65, 0x69, 0x74, 0x65, 0x6D, 0x73, 0x82, 0x01, 0x02,
            0x65, 0x6F, 0x72, 0x64, 0x65, 0x72, 0x78, 0x24,
        ] + Array("6F9619FF-8B86-D011-B42D-00C04FC964FF".utf8) + [
            0x66, 0x73, 0x68, 0x69, 0x70, 0x54, 0x6F, 0xA1, 0x64, 0x63, 0x69, 0x74, 0x79, 0x64, 0x4F, 0x73, 0x6C, 0x6F,
        ]
        let expected: SwiftCBOR.CBOR = .map([
            .utf8String("at"): .double(0.5),
            .utf8String("order"): .utf8String("6F9619FF-8B86-D011-B42D-00C04FC964FF"),
            .utf8String("email"): .utf8String("a@b.c"),
            .utf8String("items"): .array([.unsignedInt(1), .unsignedInt(2)]),
            .utf8String("shipTo"): .map([.utf8String("city"): .utf8String("Oslo")]),
        ])

        let bytes = try SensitiveCoding.$revealsValues.withValue(true) { try CBOREncoder().encode(event) }
        let actual = try SwiftCBOR.CBOR.decode(bytes)

        #expect(bytes == expectedBytes)
        #expect(actual == expected)
    }

    @Test("An encoding of one's own writes a sensitive value as null, and an optional that holds a value as that value")
    func redacted() throws {
        let order = try #require(UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF"))
        let event = Ordered(at: Date(timeIntervalSinceReferenceDate: 0.5), order: order, email: Sensitive("a@b.c"), coupon: "SPRING", items: [], shipTo: Address(city: "Oslo"))
        let expected: SwiftCBOR.CBOR = .map([
            .utf8String("at"): .double(0.5),
            .utf8String("order"): .utf8String("6F9619FF-8B86-D011-B42D-00C04FC964FF"),
            .utf8String("email"): .null,
            .utf8String("coupon"): .utf8String("SPRING"),
            .utf8String("items"): .array([]),
            .utf8String("shipTo"): .map([.utf8String("city"): .utf8String("Oslo")]),
        ])

        let bytes = try CBOREncoder().encode(event)
        let actual = try SwiftCBOR.CBOR.decode(bytes)

        #expect(actual == expected)
    }

    @Test("Any event a store's encoding writes decodes back the same, its Date exactly", .tags(.randomized))
    func roundTrip() async {
        await propertyCheck(count: 300, input: Gen.int(in: -1_000_000_000 ... 1_000_000_000), Gen.uint8().array(of: 0...12), Gen.uint8().array(of: 0...8).optional, Gen.int(in: .min ... .max).array(of: 0...6)) { tenths, email, coupon, items in
            let event = Ordered(
                at: Date(timeIntervalSinceReferenceDate: Double(tenths) / 10),
                order: UUID(uuid: (UInt8(truncatingIfNeeded: tenths), 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1)),
                email: Sensitive(String(decoding: email.map { $0 % 128 }, as: UTF8.self)),
                coupon: coupon.map { String(decoding: $0.map { $0 % 128 }, as: UTF8.self) },
                items: items,
                shipTo: Address(city: "Oslo")
            )

            let actual = try? SensitiveCoding.$revealsValues.withValue(true) {
                try CBORDecoder().decode(Ordered.self, from: try CBOREncoder().encode(event))
            }

            #expect(actual == event)
        }
    }
}

extension EventMacroCBORTests.Ordered {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.at == rhs.at && lhs.order == rhs.order && lhs.email.value == rhs.email.value && lhs.coupon == rhs.coupon && lhs.items == rhs.items && lhs.shipTo == rhs.shipTo
    }
}
