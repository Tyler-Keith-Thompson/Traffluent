// The module is compiled for macOS and Linux alone (Sources/GoogleAnalyticsEncoding).
#if os(macOS) || os(Linux)
// Property tests against a naive reference: Foundation's JSON parser reads back from the bodies
// what each generated record holds, and a model says which client each event is sent under.

import EventMacros
import Foundation
import GoogleAnalyticsEncoding
import Instrumentation
import PropertyBased
import PropertyJSON
import Sessions
import Testing
import TrackingPlans
import TraffluentTestSupport

@Suite("GoogleAnalyticsBatchEncoder: properties of any batch")
struct GoogleAnalyticsBatchEncoderPropertyTests {
    @Event(name: "generated")
    struct Generated {
        var text: String
        var count: Int
    }

    @Test("Any mix of records with and without a session sends every one, a client to a request in the order of its first record, in requests of at most the limit's count, under its session or else its own id, with session_id only for a session", .tags(.randomized))
    func clientModel() async {
        await propertyCheck(count: 300, input: Gen.uint8().optional.array(of: 0...24), Gen.uint32().array(of: 0...12)) { sessions, scalars in
            try check(sessions: sessions, scalars: scalars)
        }

        // A nested function rather than the closure's body: AGENTS.md, closures inside #expect
        // inside another closure.
        func check(sessions: [UInt8?], scalars: [UInt32]) throws {
            // Any Unicode scalar, control characters and quotes included; surrogates are skipped.
            // At most 12 scalars of 4 bytes, within the 100 bytes a value takes.
            let text = String(String.UnicodeScalarView(scalars.compactMap { Unicode.Scalar($0 % 0x11_0000) }))
            // A small count, so the batches here split as a batch of hundreds would.
            let limit = try BatchLimit(maximumRecordCount: 3, maximumByteCount: GoogleAnalyticsBatchEncoder.batchLimit.maximumByteCount, maximumRecordByteCount: GoogleAnalyticsBatchEncoder.batchLimit.maximumRecordByteCount)
            let sut = GoogleAnalyticsBatchEncoder(plan: try TrackingPlan(schemas: [Generated.schema]), limit: limit, now: { Date(timeIntervalSince1970: 1_795_442_607) })
            let batch = sessions.enumerated().map { index, session in
                var context = ServiceContext.topLevel
                // A few version 7 sessions, so records share one as a tracker's do.
                context[SessionKey.self] = session.map { UUID(uuidString: String(format: "00000000-00%02X-7000-8000-000000000000", $0 % 4))! }
                return EventRecord(event: Generated(text: text, count: index), timestamp: Date(timeIntervalSince1970: 1_795_442_607 + Double(index)), sourceLocation: nil, context: context)
            }
            // The model: each record's client is its session, or its own id without one, written
            // from the UUID's hexadecimal string; clients in the order of their first record.
            func clientID(of record: EventRecord) -> String {
                let hex = (record.context[SessionKey.self] ?? record.id).uuidString.replacingOccurrences(of: "-", with: "")
                return "\(UInt64(hex.prefix(16), radix: 16) ?? 0).\(UInt64(hex.suffix(16), radix: 16) ?? 0)"
            }
            var clients: [String] = []
            for record in batch where !clients.contains(clientID(of: record)) {
                clients.append(clientID(of: record))
            }
            let expectedRequests: [(client: String, records: [EventRecord])] = clients.flatMap { client in
                let records = batch.filter { clientID(of: $0) == client }
                return stride(from: 0, to: records.count, by: 3).map { (client, Array(records[$0 ..< min($0 + 3, records.count)])) }
            }

            let actual = sut.requests(for: batch)

            #expect(actual.skippedRecords.isEmpty)
            #expect(actual.requests.map(\.recordIDs) == expectedRequests.map { $0.records.map(\.id) })
            for (request, expected) in zip(actual.requests, expectedRequests) {
                let body = try #require(try JSONSerialization.jsonObject(with: request.body.body) as? [String: Any])
                let events = try #require(body["events"] as? [[String: Any]])
                let params = events.map { $0["params"] as? [String: Any] }
                // The texts are read with JSONDecoder: JSONSerialization drops a U+FEFF that starts
                // a string value (a Foundation bug, recorded here rather than filed: on macOS
                // whether the body holds it raw or as \uFEFF, in swift-corelibs-foundation when it
                // is raw), so a text of exactly U+FEFF would read back as "" (TRAF-138).
                struct Body: Decodable {
                    struct Event: Decodable {
                        struct Parameters: Decodable { var text: String }
                        var params: Parameters
                    }
                    var events: [Event]
                }
                let actualTexts: [String?] = try JSONDecoder().decode(Body.self, from: request.body.body).events.map(\.params.text)
                let expectedTexts: [String?] = expected.records.map { _ in text }
                let expectedSessionIDs: [Int64?] = expected.records.map { record in
                    record.context[SessionKey.self].flatMap { Int64($0.uuidString.replacingOccurrences(of: "-", with: "").prefix(12), radix: 16) }
                }
                let expectedMicros: [Int64?] = expected.records.map { Int64($0.timestamp.timeIntervalSince1970) * 1_000_000 }
                #expect(body["client_id"] as? String == expected.client)
                #expect(events.allSatisfy { $0["name"] as? String == "generated" })
                #expect(actualTexts == expectedTexts)
                #expect(params.map { $0?["count"] as? Int } == expected.records.map { ($0.event as? Generated)?.count })
                #expect(params.map { ($0?["session_id"] as? NSNumber)?.int64Value } == expectedSessionIDs)
                #expect(events.map { ($0["timestamp_micros"] as? NSNumber)?.int64Value } == expectedMicros)
                #expect(body["user_id"] == nil)
            }
        }
    }
}
#endif
