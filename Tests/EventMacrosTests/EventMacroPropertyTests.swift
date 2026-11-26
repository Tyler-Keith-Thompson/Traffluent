// Property tests against a naive reference: a generated conformance writes exactly the bytes of the
// compiler's synthesized one and of the map CBOR's value model builds, and what it encodes decodes
// to the same value.

import CBOR
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

    // The reference: the same fields, with the conformance the compiler synthesizes.
    struct SynthesizedCheckout: Codable {
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
            let bytes = try? CBOREncoder().encode(checkout)

            let actual = try? bytes.flatMap { try CBORDecoder().decode(Checkout.self, from: $0) }

            #expect(actual == checkout)
        }
    }

    @Test("Any generated event's bytes are the synthesized conformance's, and the map CBOR's value model builds", .tags(.randomized))
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
            let synthesized = try? CBOREncoder().encode(SynthesizedCheckout(checkout))
            var entries: [CBOR: CBOR] = [
                .textString("total"): CBOR(integerLiteral: Int64(checkout.total)),
                .textString("currency"): .textString(checkout.currency),
                .textString("items"): .array(checkout.items.map { CBOR(integerLiteral: Int64($0)) }),
                .textString("express"): .bool(checkout.express),
                .textString("discount"): .double(checkout.discount),
            ]
            entries[.textString("coupon")] = checkout.coupon.map { .textString($0) }
            let model = CBOR.map(entries).encode()

            let actual = try? CBOREncoder().encode(checkout)

            #expect(actual == synthesized)
            #expect(actual == model)
        }
    }
}
