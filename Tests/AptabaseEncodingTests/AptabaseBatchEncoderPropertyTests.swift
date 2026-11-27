// Property tests against naive references: Foundation's JSON decoder reads back from the bodies
// what each generated record holds, and a count of UTF-16 code units says which names and values
// Aptabase takes.

import AptabaseEncoding
import EventMacros
import Foundation
import HTTPDestinations
import Instrumentation
import PropertyBased
import PropertyJSON
import Sessions
import Testing
import TrackingPlans
import TraffluentTestSupport

@Suite("AptabaseBatchEncoder: properties of any batch")
struct AptabaseBatchEncoderPropertyTests {
    @Event(name: "generated")
    struct Generated {
        var text: String
        var position: Int
        var flag: Bool
    }

    /// An event of one property, named and valued by the test.
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

        var property: String
        var value: String

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: Key.self)
            try container.encode(value, forKey: Key(stringValue: property))
        }
    }

    @Test("Any mix of records with and without a session sends every one, in order, in requests of at most the limit's count, each with its session or id as sessionId, and its values", .tags(.randomized))
    func eventModel() async {
        await propertyCheck(count: 300, input: Gen.uint8().optional.array(of: 0...60), Gen.uint32().array(of: 0...12), Gen.bool()) { sessions, scalars, isDebug in
            try check(sessions: sessions, scalars: scalars, isDebug: isDebug)
        }

        // A nested function rather than the closure's body: AGENTS.md, closures inside #expect
        // inside another closure.
        func check(sessions: [UInt8?], scalars: [UInt32], isDebug: Bool) throws {
            // Any Unicode scalar, control characters and quotes included; surrogates are skipped.
            // At most 12 scalars, so the text is within Aptabase's 180 characters.
            let text = String(String.UnicodeScalarView(scalars.compactMap { Unicode.Scalar($0 % 0x11_0000) }))
            let now = Date(timeIntervalSince1970: 1_795_442_607)
            let sut = AptabaseBatchEncoder(isDebug: isDebug, plan: try TrackingPlan(schemas: [Generated.schema]), now: { now })
            let batch = sessions.enumerated().map { index, session in
                var context = ServiceContext.topLevel
                // A few sessions, so records share one as a tracker's do.
                context[SessionKey.self] = session.map { UUID(uuidString: String(format: "00000000-00%02X-7000-8000-000000000000", $0 % 4))! }
                // Up to an hour old, inside the 23 hours.
                return EventRecord(event: Generated(text: text, position: index, flag: index % 2 == 0), timestamp: now.addingTimeInterval(-Double(index) * 60), sourceLocation: nil, context: context)
            }
            // The model: every record is sent; sessionId is the session, or the record's id
            // without one; a Bool is a JSON boolean; systemProps are isDebug and sdkVersion, as
            // the records have no standard context.
            struct Properties: Decodable, Equatable {
                var text: String
                var position: Int
                var flag: Bool
            }
            struct SystemProperties: Decodable, Equatable {
                var isDebug: Bool
                var sdkVersion: String
            }
            struct Event: Decodable, Equatable {
                var eventName: String
                var sessionId: String
                var props: Properties
                var systemProps: SystemProperties
                var timestamp: String
            }
            let expected = try batch.enumerated().map { index, record in
                Event(
                    eventName: "generated",
                    sessionId: (record.context[SessionKey.self] ?? record.id).uuidString.lowercased(),
                    props: Properties(text: text, position: index, flag: index % 2 == 0),
                    systemProps: SystemProperties(isDebug: isDebug, sdkVersion: "Traffluent"),
                    timestamp: try record.timestamp.iso8601Timestamp
                )
            }
            let expectedRequestSizes = stride(from: 0, to: batch.count, by: 25).map { min(25, batch.count - $0) }

            let actual = sut.requests(for: batch)

            // Read with JSONDecoder: JSONSerialization drops a U+FEFF that starts a string value
            // (TRAF-138), so a text of exactly U+FEFF would read back as "".
            let requests = try actual.requests.map { try JSONDecoder().decode([Event].self, from: $0.body.body) }
            #expect(actual.skippedRecords.isEmpty)
            #expect(actual.requests.map(\.recordIDs.count) == expectedRequestSizes)
            #expect(requests.flatMap { $0 } == expected)
        }
    }

    // Letters of one, two and three UTF-8 bytes, all one UTF-16 unit, and an emoji of two units.
    static let scalars: [Unicode.Scalar] = ["a", "é", "中", "😀"]

    @Test("A property name is sent exactly when it is at most 40 UTF-16 code units, and a string value at most 180, and the record is otherwise left out", .tags(.randomized))
    func lengthRule() async {
        await propertyCheck(count: 200, input: Gen.uint8().array(of: 1...200), Gen.bool()) { picks, isName in
            try check(picks: picks, isName: isName)
        }

        // A nested function rather than the closure's body: AGENTS.md, closures inside #expect
        // inside another closure.
        func check(picks: [UInt8], isName: Bool) throws {
            let text = String(String.UnicodeScalarView(picks.map { Self.scalars[Int($0) % Self.scalars.count] }))
            // The reference: a count of the text's UTF-16 code units, done by hand.
            let units = text.unicodeScalars.reduce(0) { $0 + ($1.value > 0xFFFF ? 2 : 1) }
            let fits = units <= (isName ? 40 : 180)
            let now = Date(timeIntervalSince1970: 1_795_442_607)
            let schema = EventSchema(name: "one_property", version: 1, consentCategory: .analytics, properties: [])
            let sut = AptabaseBatchEncoder(isDebug: false, plan: try TrackingPlan(schemas: [schema]), now: { now })
            let event = isName ? OneProperty(property: text, value: "v") : OneProperty(property: "note", value: text)
            let record = EventRecord(event: event, timestamp: now, sourceLocation: nil)
            let expected: [AptabaseEncodingError]
            if fits {
                expected = []
            } else if isName {
                expected = [.propertyNameTooLong(event: "one_property", property: text)]
            } else {
                expected = [.propertyValueTooLong(event: "one_property", property: "note", length: units)]
            }

            let actual = sut.requests(for: [record])

            #expect(actual.skippedRecords.map(\.reason) == expected)
            #expect(actual.requests.flatMap(\.recordIDs) == (fits ? [record.id] : []))
        }
    }
}
