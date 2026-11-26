// Property tests against a naive reference: Foundation's JSON parser reads back from the body what
// each generated record holds, and a model says who each event is.

import EventMacros
import Foundation
import Instrumentation
import PostHogEncoding
import PropertyBased
import Sessions
import Testing
import TrackingPlans
import TraffluentTestSupport

@Suite("PostHogBatchEncoder: properties of any batch")
struct PostHogBatchEncoderPropertyTests {
    @Event(name: "generated")
    struct Generated {
        var text: String
        var count: Int
    }

    @Test("Any mix of records with and without a session sends every one, in order, under its session or else its own id, with the session as $session_id when it has one, and its uuid", .tags(.randomized))
    func distinctIDModel() async {
        await propertyCheck(count: 300, input: Gen.uint8().optional.array(of: 0...16), Gen.uint32().array(of: 0...12)) { sessions, scalars in
            try check(sessions: sessions, scalars: scalars)
        }

        // A nested function rather than the closure's body: AGENTS.md, closures inside #expect
        // inside another closure.
        func check(sessions: [UInt8?], scalars: [UInt32]) throws {
            // Any Unicode scalar, control characters and quotes included; surrogates are skipped.
            let text = String(String.UnicodeScalarView(scalars.compactMap { Unicode.Scalar($0 % 0x11_0000) }))
            let sut = PostHogBatchEncoder(projectToken: "phc_test", plan: try TrackingPlan(schemas: [Generated.schema]))
            let batch = sessions.enumerated().map { index, session in
                var context = ServiceContext.topLevel
                // A few sessions, so records share one as a tracker's do.
                context[SessionKey.self] = session.map { UUID(uuidString: String(format: "00000000-0000-4000-8000-0000000000%02X", $0 % 4))! }
                return EventRecord(event: Generated(text: text, count: index), timestamp: Date(timeIntervalSince1970: Double(index)), sourceLocation: nil, context: context)
            }
            // The model: every record is sent, under its session, or under its own id without one.
            let expectedDistinctIDs: [String?] = batch.map { ($0.context[SessionKey.self] ?? $0.id).uuidString.lowercased() }
            let expectedSessionIDs: [String?] = batch.map { $0.context[SessionKey.self]?.uuidString.lowercased() }
            let expectedUUIDs: [String?] = batch.map { $0.id.uuidString.lowercased() }
            let expectedCounts: [Int?] = Array(batch.indices)
            let expectedTexts: [String?] = Array(repeating: text, count: batch.count)

            let actual = sut.batch(of: batch)

            let body = try #require(actual.body).body
            let object = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let events = object?["batch"] as? [[String: Any]] ?? []
            let properties = events.map { $0["properties"] as? [String: Any] }
            let actualToken = object?["api_key"] as? String
            let actualDistinctIDs = events.map { $0["distinct_id"] as? String }
            let actualUUIDs = events.map { $0["uuid"] as? String }
            let actualCounts = properties.map { $0?["count"] as? Int }
            let actualTexts = properties.map { $0?["text"] as? String }
            let actualSessionIDs = properties.map { $0?["$session_id"] as? String }
            #expect(actual.skippedRecords.isEmpty)
            #expect(actualToken == "phc_test")
            #expect(actualDistinctIDs == expectedDistinctIDs)
            #expect(actualUUIDs == expectedUUIDs)
            #expect(actualCounts == expectedCounts)
            #expect(actualTexts == expectedTexts)
            #expect(actualSessionIDs == expectedSessionIDs)
        }
    }
}
