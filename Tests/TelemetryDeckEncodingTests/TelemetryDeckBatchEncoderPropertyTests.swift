// Property tests against naive references: Foundation's JSON parser reads back from the bodies what
// each generated record holds, swift-crypto's SHA256 of the identifier says what
// clientUser is, and a regular expression says which parameter names TelemetryDeck takes.

import Crypto
import EventMacros
import Foundation
import HTTPDestinations
import Instrumentation
import PropertyBased
import PropertyJSON
import Sessions
import TelemetryDeckEncoding
import Testing
import TrackingPlans
import TraffluentTestSupport

@Suite("TelemetryDeckBatchEncoder: properties of any batch")
struct TelemetryDeckBatchEncoderPropertyTests {
    @Event(name: "generated")
    struct Generated {
        var text: String
        var position: Int
    }

    /// An event of one property, named by the test, which only a hand-written `Encodable`
    /// conformance can write when the name isn't a Swift identifier.
    struct OneProperty: Event, Encodable {
        static let name = "one_property"

        struct Key: CodingKey {
            var stringValue: String
            var intValue: Int? { nil }

            init(stringValue: String) {
                self.stringValue = stringValue
            }

            init?(intValue: Int) {
                nil
            }
        }

        var parameter: String

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: Key.self)
            try container.encode("value", forKey: Key(stringValue: parameter))
        }
    }

    @Test("Any mix of records with and without a session sends every one, in order, in requests of at most the limit's count, each with its hashed session or id as clientUser, its session alone as sessionID, and its values", .tags(.randomized))
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
            let limit = try BatchLimit(maximumRecordCount: 7, maximumByteCount: TelemetryDeckBatchEncoder.batchLimit.maximumByteCount, maximumRecordByteCount: TelemetryDeckBatchEncoder.batchLimit.maximumRecordByteCount)
            let sut = try TelemetryDeckBatchEncoder(appID: "B97579B6-FFB8-4AC5-AAA7-DA5796CC5DCE", testMode: true, plan: try TrackingPlan(schemas: [Generated.schema]), limit: limit)
            let batch = sessions.enumerated().map { index, session in
                var context = ServiceContext.topLevel
                // A few sessions, so records share one as a tracker's do.
                context[SessionKey.self] = session.map { UUID(uuidString: String(format: "00000000-00%02X-7000-8000-000000000000", $0 % 4))! }
                return EventRecord(event: Generated(text: text, position: index), timestamp: Date(timeIntervalSince1970: 1_795_442_607 + Double(index)), sourceLocation: nil, context: context)
            }
            // The model: every record is sent; clientUser hashes the session, or the record's id
            // without one; only a session gives a sessionID.
            let expectedSessions: [String?] = batch.map { $0.context[SessionKey.self]?.uuidString.lowercased() }
            let expectedClientUsers: [String?] = batch.map { record in
                let identifier = (record.context[SessionKey.self] ?? record.id).uuidString.lowercased()
                return SHA256.hash(data: Data(identifier.utf8)).map { String(format: "%02x", $0) }.joined()
            }
            let expectedPositions: [Int?] = Array(batch.indices)
            let expectedTexts: [String?] = Array(repeating: text, count: batch.count)
            let expectedRequestSizes = stride(from: 0, to: batch.count, by: 7).map { min(7, batch.count - $0) }

            let actual = sut.requests(for: batch)

            let events = try actual.requests.flatMap { try JSONSerialization.jsonObject(with: $0.body.body) as? [[String: Any]] ?? [] }
            #expect(actual.skippedRecords.isEmpty)
            #expect(actual.requests.map(\.recordIDs.count) == expectedRequestSizes)
            #expect(events.allSatisfy { $0["type"] as? String == "generated" && $0["appID"] as? String == "B97579B6-FFB8-4AC5-AAA7-DA5796CC5DCE" && $0["isTestMode"] as? String == "true" })
            #expect(events.map { $0["sessionID"] as? String } == expectedSessions)
            #expect(events.map { $0["clientUser"] as? String } == expectedClientUsers)
            #expect(events.map { $0["position"] as? Int } == expectedPositions)
            #expect(events.map { $0["text"] as? String } == expectedTexts)
        }
    }

    // ASCII letters and digits, the three marks, and what TelemetryDeck refuses: a letter outside
    // ASCII, a space, punctuation, a symbol. No `t`, `c` or `p`, so no name is reserved.
    static let scalars: [Unicode.Scalar] = [
        "a", "b", "z", "A", "Q", "Z", "0", "7", "9", ".", "_", "-",
        "é", "ß", "中", " ", "/", ":", "$", "😀", "\u{301}", "\u{0}",
    ]

    @Test("A parameter name is sent exactly when it matches ^[A-Za-z0-9._-]+$, and is otherwise left out as invalidParameterName", .tags(.randomized))
    func namingRule() async {
        await propertyCheck(count: 500, input: Gen.uint8().array(of: 0...12)) { picks in
            try check(picks: picks)
        }

        // A nested function rather than the closure's body: AGENTS.md, closures inside #expect
        // inside another closure.
        func check(picks: [UInt8]) throws {
            let name = String(String.UnicodeScalarView(picks.map { Self.scalars[Int($0) % Self.scalars.count] }))
            let reference = try Regex(#"^[A-Za-z0-9._-]+$"#).matchingSemantics(.unicodeScalar)
            let isName = try reference.wholeMatch(in: name) != nil
            let schema = EventSchema(name: "one_property", version: 1, consentCategory: .analytics, properties: [])
            let sut = try TelemetryDeckBatchEncoder(appID: "B97579B6-FFB8-4AC5-AAA7-DA5796CC5DCE", testMode: false, plan: try TrackingPlan(schemas: [schema]))
            let record = EventRecord(event: OneProperty(parameter: name), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
            let expected: [TelemetryDeckEncodingError] = isName ? [] : [.invalidParameterName(event: "one_property", parameter: name)]

            let actual = sut.requests(for: [record])

            #expect(actual.skippedRecords.map(\.reason) == expected)
            #expect(actual.requests.flatMap(\.recordIDs) == (isName ? [record.id] : []))
        }
    }
}
