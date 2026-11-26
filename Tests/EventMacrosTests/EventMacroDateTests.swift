// How dates read back through the CBOR package a store uses: exactly where @Event writes them as
// the seconds they store (a Date, [Date], [Date?]), and to within a rounding of a microsecond's
// scale where the package's own tag 1 epoch time does (a Date in a Codable type of one's own, or
// in an event whose Codable conformance Swift synthesizes). Both modules name a type CBOR:
// SwiftCBOR's is always written SwiftCBOR.CBOR here.

import CBOR
import EventMacros
import Foundation
import PropertyBased
import SwiftCBOR
import Testing
import TraffluentTestSupport

@Suite("@Event: dates")
struct EventMacroDateTests {
    @Event
    struct Scheduled: Equatable {
        var slots: [Date]
        var maybe: [Date?]
        var later: [Date]?
    }

    struct Shipment: Codable, Sendable, Equatable {
        var at: Date
    }

    @Event
    struct Shipped: Equatable {
        var shipment: Shipment
    }

    struct Noted: Event, Codable, Equatable {
        var at: Date
    }

    @Test("An array of dates, or of optional dates, is written as an array of the doubles of their seconds since 2001, a nil element as null, a nil array left out")
    func arrays() throws {
        let event = Scheduled(slots: [Date(timeIntervalSinceReferenceDate: 0.25)], maybe: [Date(timeIntervalSinceReferenceDate: 0.5), nil], later: nil)
        // {"maybe": [0.5, null], "slots": [0.25]}, keys in CBOR's sorted order.
        let expectedBytes: [UInt8] = [
            0xA2,
            0x65, 0x6D, 0x61, 0x79, 0x62, 0x65, 0x82, 0xFB, 0x3F, 0xE0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xF6,
            0x65, 0x73, 0x6C, 0x6F, 0x74, 0x73, 0x81, 0xFB, 0x3F, 0xD0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        ]
        let expected: SwiftCBOR.CBOR = .map([
            .utf8String("maybe"): .array([.double(0.5), .null]),
            .utf8String("slots"): .array([.double(0.25)]),
        ])

        let bytes = try CBOREncoder().encode(event)
        let actual = try SwiftCBOR.CBOR.decode(bytes)

        #expect(bytes == expectedBytes)
        #expect(actual == expected)
    }

    @Test("An optional array of dates that holds one is written as the doubles of their seconds since 2001")
    func optionalArray() throws {
        let event = Scheduled(slots: [], maybe: [], later: [Date(timeIntervalSinceReferenceDate: -1.5)])
        let expected: SwiftCBOR.CBOR = .map([
            .utf8String("later"): .array([.double(-1.5)]),
            .utf8String("maybe"): .array([]),
            .utf8String("slots"): .array([]),
        ])

        let actual = try SwiftCBOR.CBOR.decode(try CBOREncoder().encode(event))

        #expect(actual == expected)
    }

    @Test("Arrays of dates read back exactly, whatever the seconds", .tags(.randomized))
    func arraysRoundTrip() async {
        let seconds = Gen.double(in: -1e10 ... 1e10)
        await propertyCheck(count: 300, input: seconds.array(of: 0...6), seconds.optional().array(of: 0...6), seconds.array(of: 0...6).optional()) { slots, maybe, later in
            let event = Scheduled(
                slots: slots.map(Date.init(timeIntervalSinceReferenceDate:)),
                maybe: maybe.map { $0.map(Date.init(timeIntervalSinceReferenceDate:)) },
                later: later.map { $0.map(Date.init(timeIntervalSinceReferenceDate:)) }
            )

            let actual = try? CBORDecoder().decode(Scheduled.self, from: try CBOREncoder().encode(event))

            #expect(actual == event)
        }
    }

    @Test("A Date in a Codable type of one's own, or in an event whose Codable conformance Swift synthesizes, reads back to within a microsecond-scale rounding: 0.1 s since 2001 as 0.10000002384185791")
    func packageDatesRound() throws {
        let date = Date(timeIntervalSinceReferenceDate: 0.1)
        // The package writes tag 1, seconds since 1970, whose double rounds away the bits below
        // about 1.2e-7 s at today's dates.
        let expectedSeconds: Double = 0.10000002384185791

        let nested = try CBORDecoder().decode(Shipped.self, from: try CBOREncoder().encode(Shipped(shipment: Shipment(at: date))))
        let synthesized = try CBORDecoder().decode(Noted.self, from: try CBOREncoder().encode(Noted(at: date)))

        #expect(nested.shipment.at.timeIntervalSinceReferenceDate == expectedSeconds)
        #expect(synthesized.at.timeIntervalSinceReferenceDate == expectedSeconds)
    }
}
