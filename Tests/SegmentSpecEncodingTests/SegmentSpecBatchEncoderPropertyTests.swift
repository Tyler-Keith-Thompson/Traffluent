// Property tests against a naive reference: Foundation's JSON parser reads back from the bodies
// what each generated record holds, and a model says who each call is.

import EventMacros
import Foundation
import Instrumentation
import PropertyBased
import PropertyJSON
import SegmentSpecEncoding
import Sessions
import Testing
import TrackingPlans
import TraffluentTestSupport

@Suite("SegmentSpecBatchEncoder: properties of any batch")
struct SegmentSpecBatchEncoderPropertyTests {
    @Event(name: "generated")
    struct Generated {
        var text: String
        var count: Int
    }

    @Test("Any mix of records with and without a session sends every one, in order, in requests of at most the limit's count, as track calls under its session or else its own id, with its id as messageId, its time in ISO 8601 and ip 0.0.0.0", .tags(.randomized))
    func identityModel() async {
        await propertyCheck(count: 300, input: Gen.uint8().optional.array(of: 0...24), Gen.uint32().array(of: 0...12)) { sessions, scalars in
            try check(sessions: sessions, scalars: scalars)
        }

        // A nested function rather than the closure's body: AGENTS.md, closures inside #expect
        // inside another closure.
        func check(sessions: [UInt8?], scalars: [UInt32]) throws {
            // Any Unicode scalar, control characters and quotes included; surrogates are skipped.
            let text = String(String.UnicodeScalarView(scalars.compactMap { Unicode.Scalar($0 % 0x11_0000) }))
            // A small count, so the batches here split as a batch of 2,500 would.
            let limit = try BatchLimit(maximumRecordCount: 7, maximumByteCount: SegmentSpecBatchEncoder.batchLimit.maximumByteCount, maximumRecordByteCount: SegmentSpecBatchEncoder.batchLimit.maximumRecordByteCount)
            let sut = SegmentSpecBatchEncoder(plan: try TrackingPlan(schemas: [Generated.schema]), limit: limit)
            let batch = sessions.enumerated().map { index, session in
                var context = ServiceContext.topLevel
                // A few sessions, so records share one as a tracker's do.
                context[SessionKey.self] = session.map { UUID(uuidString: String(format: "00000000-00%02X-7000-8000-000000000000", $0 % 4))! }
                return EventRecord(event: Generated(text: text, count: index), timestamp: Date(timeIntervalSince1970: 1_795_442_607 + Double(index)), sourceLocation: nil, context: context)
            }
            // The model: every record is sent, under its session, or under its own id without one.
            let expectedAnonymousIDs: [String?] = batch.map { ($0.context[SessionKey.self] ?? $0.id).uuidString.lowercased() }
            let expectedMessageIDs: [String?] = batch.map { $0.id.uuidString.lowercased() }
            let expectedTimestamps: [String?] = batch.indices.map { String(format: "2026-11-23T14:%02d:%02d.000Z", 3 + (27 + $0) / 60, (27 + $0) % 60) }
            let expectedCounts: [Int?] = Array(batch.indices)
            let expectedTexts: [String?] = Array(repeating: text, count: batch.count)
            let expectedRequestSizes = stride(from: 0, to: batch.count, by: 7).map { min(7, batch.count - $0) }

            let actual = sut.requests(for: batch)

            let calls = try actual.requests.flatMap { try (JSONSerialization.jsonObject(with: $0.body.body) as? [String: Any])?["batch"] as? [[String: Any]] ?? [] }
            let properties = calls.map { $0["properties"] as? [String: Any] }
            // The texts are read with JSONDecoder: JSONSerialization drops a U+FEFF that starts a
            // string value (a Foundation bug, recorded here rather than filed: on macOS whether the
            // body holds it raw or as \uFEFF, in swift-corelibs-foundation when it is raw), so a
            // text of exactly U+FEFF read back as "" though the body held EF BB BF (TRAF-138).
            struct Body: Decodable {
                struct Call: Decodable {
                    struct Properties: Decodable { var text: String }
                    var properties: Properties
                }
                var batch: [Call]
            }
            let actualTexts: [String?] = try actual.requests.flatMap { try JSONDecoder().decode(Body.self, from: $0.body.body).batch.map(\.properties.text) }
            #expect(actual.skippedRecords.isEmpty)
            #expect(actual.requests.map(\.recordIDs.count) == expectedRequestSizes)
            #expect(calls.allSatisfy { $0["type"] as? String == "track" && $0["event"] as? String == "generated" })
            #expect(calls.allSatisfy { ($0["context"] as? [String: Any])?["ip"] as? String == "0.0.0.0" })
            #expect(calls.map { $0["anonymousId"] as? String } == expectedAnonymousIDs)
            #expect(calls.map { $0["messageId"] as? String } == expectedMessageIDs)
            #expect(calls.map { $0["timestamp"] as? String } == expectedTimestamps)
            #expect(properties.map { $0?["count"] as? Int } == expectedCounts)
            #expect(actualTexts == expectedTexts)
            #expect(calls.allSatisfy { $0["userId"] == nil && $0["traits"] == nil })
        }
    }
}
