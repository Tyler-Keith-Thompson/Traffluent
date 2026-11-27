// Property tests against a naive reference: Foundation's JSON parser reads back from the bodies
// what each generated record holds, and a model says what each event carries.

import EventMacros
import Foundation
import Instrumentation
import PropertyBased
import PropertyJSON
import Sessions
import SnowplowEncoding
import Testing
import TrackingPlans
import TraffluentTestSupport

@Suite("SnowplowBatchEncoder: properties of any batch")
struct SnowplowBatchEncoderPropertyTests {
    @Event(name: "generated")
    struct Generated {
        var text: String
        var count: Int
    }

    @Test("Any mix of records with and without a session sends every one, in order, in requests of at most the limit's count, as self-describing events with only their session as sid, their id as eid and their time as dtm and ttm", .tags(.randomized))
    func eventModel() async {
        await propertyCheck(count: 300, input: Gen.uint8().optional.array(of: 0...24), Gen.uint32().array(of: 0...12)) { sessions, scalars in
            try check(sessions: sessions, scalars: scalars)
        }

        // A nested function rather than the closure's body: AGENTS.md, closures inside #expect
        // inside another closure.
        func check(sessions: [UInt8?], scalars: [UInt32]) throws {
            // Any Unicode scalar, control characters and quotes included; surrogates are skipped.
            let text = String(String.UnicodeScalarView(scalars.compactMap { Unicode.Scalar($0 % 0x11_0000) }))
            // A small count, so the batches here split as a batch of hundreds would.
            let limit = try BatchLimit(maximumRecordCount: 7, maximumByteCount: SnowplowBatchEncoder.batchLimit.maximumByteCount, maximumRecordByteCount: SnowplowBatchEncoder.batchLimit.maximumRecordByteCount)
            let sut = try SnowplowBatchEncoder(vendor: "com.example", appID: "shop", plan: try TrackingPlan(schemas: [Generated.schema]), limit: limit)
            let batch = sessions.enumerated().map { index, session in
                var context = ServiceContext.topLevel
                // A few sessions, so records share one as a tracker's do.
                context[SessionKey.self] = session.map { UUID(uuidString: String(format: "00000000-00%02X-7000-8000-000000000000", $0 % 4))! }
                return EventRecord(event: Generated(text: text, count: index), timestamp: Date(timeIntervalSince1970: 1_795_442_607 + Double(index)), sourceLocation: nil, context: context)
            }
            // The model: every record is sent, with its session as sid or no sid without one.
            let expectedSessions: [String?] = batch.map { $0.context[SessionKey.self]?.uuidString.lowercased() }
            let expectedEventIDs: [String?] = batch.map { $0.id.uuidString.lowercased() }
            let expectedTimes: [String?] = batch.indices.map { String(1_795_442_607_000 + 1000 * $0) }
            let expectedCounts: [Int?] = Array(batch.indices)
            let expectedTexts: [String?] = Array(repeating: text, count: batch.count)
            let expectedSchemas: [String?] = Array(repeating: "iglu:com.example/generated/jsonschema/1-0-0", count: batch.count)
            let expectedRequestSizes = stride(from: 0, to: batch.count, by: 7).map { min(7, batch.count - $0) }

            let actual = sut.requests(for: batch)

            let events = try actual.requests.flatMap { try (JSONSerialization.jsonObject(with: $0.body.body) as? [String: Any])?["data"] as? [[String: Any]] ?? [] }
            let selfDescribing = try events.map { event -> [String: Any]? in
                let text = try #require(event["ue_pr"] as? String)
                let wrapper = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
                return wrapper?["data"] as? [String: Any]
            }
            let data = selfDescribing.map { $0?["data"] as? [String: Any] }
            #expect(actual.skippedRecords.isEmpty)
            #expect(actual.requests.map(\.recordIDs.count) == expectedRequestSizes)
            #expect(events.allSatisfy { $0["e"] as? String == "ue" && $0["aid"] as? String == "shop" && $0["ip"] as? String == "0.0.0.0" })
            #expect(events.allSatisfy { $0.values.allSatisfy { $0 is String } })
            #expect(events.map { $0["sid"] as? String } == expectedSessions)
            #expect(events.map { $0["eid"] as? String } == expectedEventIDs)
            #expect(events.map { $0["dtm"] as? String } == expectedTimes)
            #expect(events.map { $0["ttm"] as? String } == expectedTimes)
            #expect(selfDescribing.map { $0?["schema"] as? String } == expectedSchemas)
            #expect(data.map { $0?["count"] as? Int } == expectedCounts)
            #expect(data.map { $0?["text"] as? String } == expectedTexts)
            #expect(events.allSatisfy { $0["duid"] == nil && $0["uid"] == nil && $0["stm"] == nil })
        }
    }
}
