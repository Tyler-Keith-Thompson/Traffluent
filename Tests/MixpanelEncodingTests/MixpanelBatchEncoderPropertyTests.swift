// Property tests against a naive reference: Foundation's JSON parser reads back from the bodies
// what each generated record holds, and a model says who each event is.

import EventMacros
import Foundation
import Instrumentation
import MixpanelEncoding
import PropertyBased
import PropertyJSON
import Sessions
import Testing
import TrackingPlans
import TraffluentTestSupport

@Suite("MixpanelBatchEncoder: properties of any batch")
struct MixpanelBatchEncoderPropertyTests {
    @Event(name: "generated")
    struct Generated {
        var text: String
        var count: Int
    }

    @Test("Any mix of records with and without a session sends every one, in order, in requests of at most the limit's count, under its session or else its own id, with $device_id only for a session, a valid $insert_id, the token and ip 0", .tags(.randomized))
    func identityModel() async {
        await propertyCheck(count: 300, input: Gen.uint8().optional.array(of: 0...24), Gen.uint32().array(of: 0...12)) { sessions, scalars in
            try check(sessions: sessions, scalars: scalars)
        }

        // A nested function rather than the closure's body: AGENTS.md, closures inside #expect
        // inside another closure.
        func check(sessions: [UInt8?], scalars: [UInt32]) throws {
            // Any Unicode scalar, control characters and quotes included; surrogates are skipped.
            let text = String(String.UnicodeScalarView(scalars.compactMap { Unicode.Scalar($0 % 0x11_0000) }))
            // A small count, so the batches here split as a batch of 2,000 would.
            let limit = try BatchLimit(maximumRecordCount: 7, maximumByteCount: MixpanelBatchEncoder.batchLimit.maximumByteCount, maximumRecordByteCount: MixpanelBatchEncoder.batchLimit.maximumRecordByteCount)
            let sut = MixpanelBatchEncoder(projectToken: "testprojecttoken", plan: try TrackingPlan(schemas: [Generated.schema]), limit: limit)
            let batch = sessions.enumerated().map { index, session in
                var context = ServiceContext.topLevel
                // A few sessions, so records share one as a tracker's do.
                context[SessionKey.self] = session.map { UUID(uuidString: String(format: "00000000-00%02X-7000-8000-000000000000", $0 % 4))! }
                return EventRecord(event: Generated(text: text, count: index), timestamp: Date(timeIntervalSince1970: 1_795_442_607 + Double(index)), sourceLocation: nil, context: context)
            }
            // The model: every record is sent, under its session, or under its own id without one.
            let expectedDistinctIDs: [String?] = batch.map { ($0.context[SessionKey.self] ?? $0.id).uuidString.lowercased() }
            let expectedDeviceIDs: [String?] = batch.map { $0.context[SessionKey.self]?.uuidString.lowercased() }
            let expectedInsertIDs: [String?] = batch.map { $0.id.uuidString.lowercased() }
            let expectedTimes: [Int?] = batch.indices.map { 1_795_442_607_000 + $0 * 1_000 }
            let expectedCounts: [Int?] = Array(batch.indices)
            let expectedTexts: [String?] = Array(repeating: text, count: batch.count)
            let expectedRequestSizes = stride(from: 0, to: batch.count, by: 7).map { min(7, batch.count - $0) }
            let insertIDForm = /[0-9a-z-]{1,36}/

            let actual = sut.requests(for: batch)

            let events = try actual.requests.flatMap { try JSONSerialization.jsonObject(with: $0.body.body) as? [[String: Any]] ?? [] }
            let properties = events.map { $0["properties"] as? [String: Any] }
            let actualNames = events.map { $0["event"] as? String }
            let actualTokens = properties.map { $0?["token"] as? String }
            let actualIPs = properties.map { $0?["ip"] as? String }
            let actualDistinctIDs = properties.map { $0?["distinct_id"] as? String }
            let actualDeviceIDs = properties.map { $0?["$device_id"] as? String }
            let actualInsertIDs = properties.map { $0?["$insert_id"] as? String }
            let actualTimes = properties.map { ($0?["time"] as? NSNumber)?.intValue }
            let actualCounts = properties.map { $0?["count"] as? Int }
            // The texts are read with JSONDecoder: JSONSerialization drops a U+FEFF that starts a
            // string value (a Foundation bug, recorded here rather than filed: on macOS whether the
            // body holds it raw or as \uFEFF, in swift-corelibs-foundation when it is raw), so a
            // text of exactly U+FEFF would read back as "" (TRAF-138).
            struct Event: Decodable {
                struct Properties: Decodable { var text: String }
                var properties: Properties
            }
            let actualTexts: [String?] = try actual.requests.flatMap { try JSONDecoder().decode([Event].self, from: $0.body.body).map(\.properties.text) }
            #expect(actual.skippedRecords.isEmpty)
            #expect(actual.requests.map(\.recordIDs.count) == expectedRequestSizes)
            #expect(actualNames.allSatisfy { $0 == "generated" })
            #expect(actualTokens.allSatisfy { $0 == "testprojecttoken" })
            #expect(actualIPs.allSatisfy { $0 == "0" })
            #expect(actualDistinctIDs == expectedDistinctIDs)
            #expect(actualDeviceIDs == expectedDeviceIDs)
            #expect(actualInsertIDs == expectedInsertIDs)
            #expect(actualInsertIDs.allSatisfy { ($0?.wholeMatch(of: insertIDForm)) != nil })
            #expect(actualTimes == expectedTimes)
            #expect(actualCounts == expectedCounts)
            #expect(actualTexts == expectedTexts)
            #expect(properties.allSatisfy { $0?["$user_id"] == nil })
        }
    }
}
