// Property tests against a naive reference: Foundation's JSON parser reads back from the body the
// values each generated event holds.

import CollectorEncoding
import EventMacros
import Foundation
import Instrumentation
import PropertyBased
import Testing
import TrackingPlans
import TraffluentTestSupport

@Suite("CollectorBatchEncoder: properties of any event")
struct CollectorBatchEncoderPropertyTests {
    @Event(name: "generated")
    struct Generated {
        var text: String
        var count: Int
        var ratio: Double
        var tags: [String]
        var coupon: String?
    }

    @Test("Foundation's JSON parser reads back every value of any generated event", .tags(.randomized))
    func readsBack() async throws {
        await propertyCheck(count: 300, input: Gen.uint32().array(of: 0...12), Gen.int(in: .min ... .max), Gen.int(in: -1_000_000...1_000_000), Gen.uint8().array(of: 0...6).array(of: 0...4), Gen.uint8().array(of: 0...6).optional) { scalars, count, ratio, tags, coupon in
            // Any Unicode scalar, control characters and quotes included; surrogates are skipped.
            let text = String(String.UnicodeScalarView(scalars.compactMap { Unicode.Scalar($0 % 0x11_0000) }))
            let event = Generated(
                text: text,
                count: count,
                ratio: Double(ratio) / 1000,
                tags: tags.map { String(decoding: $0.map { $0 % 128 }, as: UTF8.self) },
                coupon: coupon.map { String(decoding: $0.map { $0 % 128 }, as: UTF8.self) }
            )
            let sut = CollectorBatchEncoder(plan: try TrackingPlan(schemas: [Generated.schema]), instrument: NoOpInstrument())
            let record = EventRecord(event: event, timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)

            let body = sut.batch(of: [record]).body?.body
            let object = body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let records = object?["records"] as? [[String: Any]]
            let actual = records?.first?["properties"] as? [String: Any]
            // The text is read with JSONDecoder: JSONSerialization drops a U+FEFF that starts a
            // string value (a Foundation bug, recorded here rather than filed: on macOS whether the
            // body holds it raw or as \uFEFF, in swift-corelibs-foundation when it is raw), so a
            // text of exactly U+FEFF would read back as "" (TRAF-138).
            struct Body: Decodable {
                struct Record: Decodable {
                    struct Properties: Decodable { var text: String }
                    var properties: Properties
                }
                var records: [Record]
            }
            let actualText = body.flatMap { try? JSONDecoder().decode(Body.self, from: $0) }?.records.first?.properties.text

            #expect(actualText == event.text)
            #expect((actual?["count"] as? NSNumber)?.int64Value == Int64(event.count))
            #expect((actual?["ratio"] as? NSNumber)?.doubleValue == event.ratio)
            #expect(actual?["tags"] as? [String] == event.tags)
            if let coupon = event.coupon {
                #expect(actual?["coupon"] as? String == coupon)
            } else {
                #expect(actual?["coupon"] is NSNull)
            }
        }
    }

    @Event(name: "unlisted")
    struct Unlisted {
        var count: Int
    }

    @Test("Any mix of listed and unlisted records encodes as the listed ones alone, the unlisted skipped in order", .tags(.randomized))
    func skipsUnlisted() async throws {
        await propertyCheck(count: 300, input: Gen.bool().array(of: 0...16)) { listed in
            let sut = CollectorBatchEncoder(plan: try TrackingPlan(schemas: [Generated.schema]), instrument: NoOpInstrument())
            let batch = listed.enumerated().map { index, isListed in
                let event: any Event = isListed
                    ? Generated(text: "\(index)", count: index, ratio: 0, tags: [], coupon: nil)
                    : Unlisted(count: index)
                return EventRecord(event: event, timestamp: Date(timeIntervalSince1970: Double(index)), sourceLocation: nil)
            }
            // The naive reference: the listed records alone, encoded as a batch of their own.
            let kept = zip(batch, listed).filter(\.1).map(\.0)
            let expectedBody = kept.isEmpty && !batch.isEmpty ? nil : sut.batch(of: kept).body
            let expectedSkipped = zip(batch, listed).filter { !$0.1 }.map(\.0.id)

            let actual = sut.batch(of: batch)

            #expect(actual.body == expectedBody)
            #expect(actual.skippedRecords.map(\.recordID) == expectedSkipped)
        }
    }
}
