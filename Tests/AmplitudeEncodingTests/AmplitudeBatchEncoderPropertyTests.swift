// Property tests against a naive reference: Foundation's JSON parser reads back from the bodies
// what each generated record holds, and a model says who each event is and when its session began.

import AmplitudeEncoding
import EventMacros
import Foundation
import Instrumentation
import PropertyBased
import Sessions
import Testing
import TrackingPlans
import TraffluentTestSupport

@Suite("AmplitudeBatchEncoder: properties of any batch")
struct AmplitudeBatchEncoderPropertyTests {
    @Event(name: "generated")
    struct Generated {
        var text: String
        var count: Int
    }

    @Test("Any mix of records with and without a session sends every one, in order, in requests of at most 10, under its session or else its own id, with the session's start as session_id when it has one, and its insert_id", .tags(.randomized))
    func deviceIDModel() async {
        await propertyCheck(count: 300, input: Gen.uint8().optional.array(of: 0...24), Gen.uint32().array(of: 0...12)) { sessions, scalars in
            try check(sessions: sessions, scalars: scalars)
        }

        // A nested function rather than the closure's body: AGENTS.md, closures inside #expect
        // inside another closure.
        func check(sessions: [UInt8?], scalars: [UInt32]) throws {
            // Any Unicode scalar, control characters and quotes included; surrogates are skipped.
            let text = String(String.UnicodeScalarView(scalars.compactMap { Unicode.Scalar($0 % 0x11_0000) }))
            let sut = AmplitudeBatchEncoder(apiKey: "test-api-key", plan: try TrackingPlan(schemas: [Generated.schema]))
            let batch = sessions.enumerated().map { index, session in
                var context = ServiceContext.topLevel
                // A few version 7 sessions, so records share one as a tracker's do; the first 48
                // bits are the start, here the session's number of milliseconds since 1970.
                context[SessionKey.self] = session.map { UUID(uuidString: String(format: "00000000-00%02X-7000-8000-000000000000", $0 % 4))! }
                return EventRecord(event: Generated(text: text, count: index), timestamp: Date(timeIntervalSince1970: Double(index)), sourceLocation: nil, context: context)
            }
            // The model: every record is sent, under its session, or under its own id without one,
            // and a session's start is its number.
            let expectedDeviceIDs: [String?] = batch.map { ($0.context[SessionKey.self] ?? $0.id).uuidString.lowercased() }
            let expectedSessionIDs: [Int?] = sessions.map { $0.map { Int($0 % 4) } }
            let expectedInsertIDs: [String?] = batch.map { $0.id.uuidString.lowercased() }
            let expectedTimes: [Int?] = batch.indices.map { $0 * 1_000 }
            let expectedCounts: [Int?] = Array(batch.indices)
            let expectedTexts: [String?] = Array(repeating: text, count: batch.count)
            let expectedRequestSizes = stride(from: 0, to: batch.count, by: 10).map { min(10, batch.count - $0) }

            let actual = sut.requests(for: batch)

            let objects = try actual.requests.map { try JSONSerialization.jsonObject(with: $0.body.body) as? [String: Any] }
            let events = objects.flatMap { $0?["events"] as? [[String: Any]] ?? [] }
            let properties = events.map { $0["event_properties"] as? [String: Any] }
            let actualKeys = objects.map { $0?["api_key"] as? String }
            let actualDeviceIDs = events.map { $0["device_id"] as? String }
            let actualSessionIDs = events.map { ($0["session_id"] as? NSNumber)?.intValue }
            let actualInsertIDs = events.map { $0["insert_id"] as? String }
            let actualTimes = events.map { ($0["time"] as? NSNumber)?.intValue }
            let actualCounts = properties.map { $0?["count"] as? Int }
            // The texts are read with JSONDecoder: JSONSerialization drops a U+FEFF that starts a
            // string value (a Foundation bug, recorded here rather than filed: on macOS whether the
            // body holds it raw or as \uFEFF, in swift-corelibs-foundation when it is raw), so a
            // text of exactly U+FEFF would read back as "" (TRAF-138).
            struct Body: Decodable {
                struct Event: Decodable {
                    struct Properties: Decodable { var text: String }
                    var event_properties: Properties
                }
                var events: [Event]
            }
            let actualTexts: [String?] = try actual.requests.flatMap { try JSONDecoder().decode(Body.self, from: $0.body.body).events.map(\.event_properties.text) }
            #expect(actual.skippedRecords.isEmpty)
            #expect(actual.requests.map(\.recordIDs.count) == expectedRequestSizes)
            #expect(actualKeys.allSatisfy { $0 == "test-api-key" })
            #expect(actualDeviceIDs == expectedDeviceIDs)
            // Amplitude removes a device_id shorter than 5 characters.
            #expect(actualDeviceIDs.allSatisfy { ($0?.count ?? 0) >= 5 })
            #expect(actualSessionIDs == expectedSessionIDs)
            #expect(actualInsertIDs == expectedInsertIDs)
            #expect(actualTimes == expectedTimes)
            #expect(actualCounts == expectedCounts)
            #expect(actualTexts == expectedTexts)
            #expect(events.allSatisfy { $0["user_id"] == nil })
        }
    }
}
