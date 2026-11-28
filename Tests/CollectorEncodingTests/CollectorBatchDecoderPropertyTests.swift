// Property tests against a naive reference: the records a batch was encoded from, compared with
// the records its body decodes to, field by field, and the body encoded again, byte for byte.

import CollectorEncoding
import EventMacros
import Foundation
import Generators
import Instrumentation
import PropertyBased
import Sampling
import Sessions
import StandardContext
import Testing
import Trackers
import TrackingPlans
import TraffluentTestSupport

// Private: its events share their names with other events of this test target, and @Event
// leaves a private type's events out of the link check of names (DefiningEvents, Limits).
@Suite("CollectorBatchDecoder: properties of any batch")
private struct CollectorBatchDecoderPropertyTests {
    @Event(name: "purchased")
    struct Purchased: Equatable {
        var sku: String
        var quantity: Int
        var price: Double
        var weight: Float
        var big: UInt64
        var at: Date
        var deliveries: [Date?]
        var tags: [String]
        var coupon: String?
        var email: Sensitive<String>

        // Dates by their millisecond, all the body holds of them.
        static func == (lhs: Purchased, rhs: Purchased) -> Bool {
            func millisecond(_ date: Date?) -> Double? {
                date.map { ($0.timeIntervalSince1970 * 1000).rounded(.down) }
            }
            return lhs.sku == rhs.sku && lhs.quantity == rhs.quantity && lhs.price == rhs.price && lhs.weight == rhs.weight
                && lhs.big == rhs.big && millisecond(lhs.at) == millisecond(rhs.at) && lhs.deliveries.map(millisecond) == rhs.deliveries.map(millisecond)
                && lhs.tags == rhs.tags && lhs.coupon == rhs.coupon && lhs.email.value == rhs.email.value
        }
    }

    @Event(name: "opened", version: 3)
    struct Opened: Equatable {
        var count: Int64
        var flag: Bool
    }

    @Test("Any batch of known events decodes to its records, and encodes again to the same bytes", .tags(.randomized))
    func roundTrip() async throws {
        await propertyCheck(count: 300, input: Gen.uint64(in: .min ... .max)) { seed in
            try check(seed: seed)
        }

        // Any date within about 4,400 years of 1970, fractions of a millisecond included, which the
        // body rounds down.
        func date(_ random: inout Xoshiro256StarStar) -> Date {
            Date(timeIntervalSince1970: random.uniform(in: -140_000_000_000 ..< 140_000_000_000))
        }

        func text(_ random: inout Xoshiro256StarStar) -> String {
            // Any Unicode scalar but a surrogate, control characters and quotes included.
            let scalars = (0 ..< random.integer(in: 0 ... 8)).compactMap { _ in Unicode.Scalar(UInt32(random.integer(in: 0 ... 0x10_FFFF))) }
            return String(String.UnicodeScalarView(scalars))
        }

        func uuid(_ random: inout Xoshiro256StarStar) -> UUID {
            let high = random.next()
            let low = random.next()
            return UUID(uuid: withUnsafeBytes(of: (high, low)) { bytes in
                (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15])
            })
        }

        func event(_ random: inout Xoshiro256StarStar) -> any Event {
            guard random.bernoulli(0.7) else {
                return Opened(count: Int64(bitPattern: random.next()), flag: random.bernoulli(0.5))
            }
            return Purchased(
                sku: text(&random),
                quantity: random.integer(in: Int.min ... Int.max),
                price: random.bernoulli(0.3) ? Double(random.integer(in: -1_000 ... 1_000)) : random.uniform(in: -1e6 ..< 1e6),
                weight: Float(random.uniform(in: 0 ..< 100)),
                // Up to Int64.max: a larger UInt64 is written as the nearest Double, and reads back
                // as that, which numbersRoundTrip in CollectorBatchDecoderTests pins.
                big: random.next() >> 1,
                at: date(&random),
                deliveries: (0 ..< random.integer(in: 0 ... 3)).map { _ in random.bernoulli(0.3) ? nil : date(&random) },
                tags: (0 ..< random.integer(in: 0 ... 3)).map { _ in text(&random) },
                coupon: random.bernoulli(0.5) ? text(&random) : nil,
                email: Sensitive(text(&random))
            )
        }

        func context(_ random: inout Xoshiro256StarStar) throws -> ServiceContext {
            var context = ServiceContext.topLevel
            if random.bernoulli(0.5) {
                context[SessionKey.self] = uuid(&random)
            }
            if random.bernoulli(0.3) {
                context[ApplicationKey.self] = ApplicationKey.Value(
                    bundleIdentifier: random.bernoulli(0.5) ? text(&random) : nil,
                    version: random.bernoulli(0.5) ? text(&random) : nil,
                    build: random.bernoulli(0.5) ? text(&random) : nil
                )
            }
            if random.bernoulli(0.3) {
                let formFactors = DeviceKey.Value.FormFactor.allCases
                context[DeviceKey.self] = DeviceKey.Value(model: text(&random), formFactor: formFactors[random.integer(in: 0 ... formFactors.count - 1)])
            }
            if random.bernoulli(0.3) {
                let networks = NetworkKey.Value.allCases
                context[NetworkKey.self] = networks[random.integer(in: 0 ... networks.count - 1)]
            }
            if random.bernoulli(0.3) {
                context[OperatingSystemKey.self] = OperatingSystemKey.Value(name: text(&random), version: text(&random))
            }
            if random.bernoulli(0.3) {
                context[SampleRateKey.self] = try SampleRate(random.uniform(in: 0 ..< 1))
            }
            if random.bernoulli(0.3) {
                context[VendorIdentifierKey.self] = Sensitive(uuid(&random))
            }
            return context
        }

        func check(seed: UInt64) throws {
            var random = Xoshiro256StarStar(seed: seed)
            let plan = try TrackingPlan(schemas: [Purchased.schema, Opened.schema])
            let encoder = CollectorBatchEncoder(plan: plan, instrument: NoOpInstrument())
            let sut = try CollectorBatchDecoder(plan: plan, events: [Purchased.self, Opened.self], instrument: NoOpInstrument())
            let batch = try (0 ..< random.integer(in: 0 ... 8)).map { _ in
                var record = EventRecord(
                    id: uuid(&random),
                    event: event(&random),
                    timestamp: date(&random),
                    sourceLocation: nil,
                    context: try context(&random),
                    isRedelivered: random.bernoulli(0.2)
                )
                record.revealsSensitiveValues = true
                return record
            }
            let encoded = encoder.batch(of: batch)
            let body = try #require(encoded.body?.body)

            let actual = try sut.batch(from: body)

            #expect(encoded.skippedRecords.isEmpty)
            #expect(actual.undecodedRecords.isEmpty)
            #expect(actual.records.map(\.id) == batch.map(\.id))
            #expect(actual.records.map { ($0.timestamp.timeIntervalSince1970 * 1000).rounded(.down) } == batch.map { ($0.timestamp.timeIntervalSince1970 * 1000).rounded(.down) })
            #expect(actual.records.map(\.isRedelivered) == batch.map(\.isRedelivered))
            #expect(actual.records.map { $0.context[SessionKey.self] } == batch.map { $0.context[SessionKey.self] })
            #expect(actual.records.map { $0.context[ApplicationKey.self] } == batch.map { $0.context[ApplicationKey.self] })
            #expect(actual.records.map { $0.context[DeviceKey.self] } == batch.map { $0.context[DeviceKey.self] })
            #expect(actual.records.map { $0.context[NetworkKey.self] } == batch.map { $0.context[NetworkKey.self] })
            #expect(actual.records.map { $0.context[SampleRateKey.self] } == batch.map { $0.context[SampleRateKey.self] })
            for (decoded, original) in zip(actual.records, batch) {
                if let expected = original.event as? Purchased {
                    #expect(decoded.event as? Purchased == expected)
                } else {
                    #expect(decoded.event as? Opened == original.event as? Opened)
                }
            }
            #expect(encoder.batch(of: actual.records).body?.body == body)
        }
    }

    @Event(name: "refunded")
    struct Refunded {
        var amount: Int
    }

    @Test("Any mix of known and unknown records decodes the known ones in order and reports the unknown ones by offset", .tags(.randomized))
    func mixedRecords() async throws {
        await propertyCheck(count: 300, input: Gen.bool().array(of: 0...16)) { known in
            let plan = try TrackingPlan(schemas: [Opened.schema, Refunded.schema])
            let encoder = CollectorBatchEncoder(plan: plan, instrument: NoOpInstrument())
            let sut = try CollectorBatchDecoder(plan: plan, events: [Opened.self], instrument: NoOpInstrument())
            let batch = known.enumerated().map { index, isKnown in
                EventRecord(event: isKnown ? Opened(count: Int64(index), flag: false) as any Event : Refunded(amount: index), timestamp: Date(timeIntervalSince1970: Double(index)), sourceLocation: nil)
            }
            let body = encoder.batch(of: batch).body?.body ?? Data(#"{"records":[]}"#.utf8)
            // The naive reference: the known records alone, and the offsets of the rest.
            let expectedIDs = zip(batch, known).filter(\.1).map(\.0.id)
            let expectedUndecoded = known.enumerated().filter { !$0.element }.map { offset, _ in
                UndecodedRecord(offset: offset, recordID: batch[offset].id, eventName: "refunded", reason: .unknownEvent(name: "refunded"))
            }

            let actual = try sut.batch(from: body)

            #expect(actual.records.map(\.id) == expectedIDs)
            #expect(actual.undecodedRecords == expectedUndecoded)
        }
    }
}
