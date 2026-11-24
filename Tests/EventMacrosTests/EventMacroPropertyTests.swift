// Property tests against a naive reference: a generated conformance writes exactly the bytes of the
// hand-written one, and what it encodes decodes to the same value.

import EventMacros
import PropertyBased
import Testing
import TraffluentTestSupport

@Suite("@Event: properties")
struct EventMacroPropertyTests {
    @Event
    struct Checkout: Equatable {
        var total: Int
        var currency: String
        var coupon: String?
        var items: [UInt32]
        var express: Bool
        var discount: Double
    }

    // The reference: the same fields, encoded by hand as BinaryCodable's documentation shows.
    struct HandWrittenCheckout: BinaryCodable {
        var total: Int
        var currency: String
        var coupon: String?
        var items: [UInt32]
        var express: Bool
        var discount: Double

        init(_ checkout: Checkout) {
            total = checkout.total
            currency = checkout.currency
            coupon = checkout.coupon
            items = checkout.items
            express = checkout.express
            discount = checkout.discount
        }

        func encode(to encoder: inout BinaryEncoder) {
            encoder.encodeMap { map in
                map.encode(total, forKey: "total")
                map.encode(currency, forKey: "currency")
                map.encode(coupon, forKey: "coupon")
                map.encode(items, forKey: "items")
                map.encode(express, forKey: "express")
                map.encode(discount, forKey: "discount")
            }
        }

        init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
            var map = try decoder.decodeMap()
            total = try map.decode(forKey: "total")
            currency = try map.decode(forKey: "currency")
            coupon = try map.decode(forKey: "coupon")
            items = try map.decode(forKey: "items")
            express = try map.decode(forKey: "express")
            discount = try map.decode(forKey: "discount")
        }
    }

    @Test("Any generated event decodes to the value encoded", .tags(.randomized))
    func roundTrip() async {
        await propertyCheck(count: 300, input: Gen.int(in: .min ... .max), Gen.uint8().array(of: 0...12), Gen.uint8().array(of: 0...12).optional, Gen.uint32().array(of: 0...8), Gen.bool, Gen.int(in: -1_000_000...1_000_000)) { total, currency, coupon, items, express, discount in
            let checkout = Checkout(
                total: total,
                currency: String(decoding: currency.map { $0 % 128 }, as: UTF8.self),
                coupon: coupon.map { String(decoding: $0.map { $0 % 128 }, as: UTF8.self) },
                items: items,
                express: express,
                discount: Double(discount) / 100
            )
            var encoder = BinaryEncoder()
            checkout.encode(to: &encoder)
            var decoder = BinaryDecoder(encoder.bytes)

            let actual = try? Checkout(from: &decoder)

            #expect(actual == checkout)
            #expect(decoder.isAtEnd)
        }
    }

    @Test("Any generated event's bytes are the hand-written conformance's", .tags(.randomized))
    func matchesHandWritten() async {
        await propertyCheck(count: 300, input: Gen.int(in: .min ... .max), Gen.uint8().array(of: 0...12), Gen.uint8().array(of: 0...12).optional, Gen.uint32().array(of: 0...8), Gen.bool, Gen.int(in: -1_000_000...1_000_000)) { total, currency, coupon, items, express, discount in
            let checkout = Checkout(
                total: total,
                currency: String(decoding: currency.map { $0 % 128 }, as: UTF8.self),
                coupon: coupon.map { String(decoding: $0.map { $0 % 128 }, as: UTF8.self) },
                items: items,
                express: express,
                discount: Double(discount) / 100
            )
            var reference = BinaryEncoder()
            HandWrittenCheckout(checkout).encode(to: &reference)
            let expected = reference.bytes
            var sut = BinaryEncoder()

            checkout.encode(to: &sut)

            #expect(sut.bytes == expected)
        }
    }
}
