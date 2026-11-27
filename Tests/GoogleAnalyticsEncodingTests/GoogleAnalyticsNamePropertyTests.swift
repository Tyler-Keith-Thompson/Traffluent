// The module is compiled for macOS and Linux alone (Sources/GoogleAnalyticsEncoding).
#if os(macOS) || os(Linux)
// A property test against a naive reference: the naming rule as a regular expression over Unicode
// scalars, ^\p{L}[\p{L}\p{N}_]*$, and at most 40 bytes of UTF-8.

import Events
import Foundation
import GoogleAnalyticsEncoding
import Instrumentation
import PropertyBased
import Testing
import TrackingPlans
import TraffluentTestSupport

@Suite("GoogleAnalyticsBatchEncoder: the naming rule")
struct GoogleAnalyticsNamePropertyTests {
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

    // Letters of several scripts and kinds, numbers of each kind, `_`, and what the rule refuses:
    // punctuation, symbols, a combining mark, a space and a format character. No `f`, `g` or `s`,
    // so no name has a reserved prefix or is session_id.
    static let scalars: [Unicode.Scalar] = [
        "a", "b", "z", "A", "Q", "Z", "é", "ß", "中", "ǅ", "ʰ", "Ω",
        "0", "7", "٣", "１", "²", "½", "Ⅳ", "_",
        "-", ".", " ", "$", "©", "😀", "\u{301}", "\u{200B}", "‿",
    ]

    @Test("A parameter name is sent exactly when it matches ^\\p{L}[\\p{L}\\p{N}_]*$ in 40 bytes of UTF-8 or fewer, and is otherwise left out as invalidParameterName", .tags(.randomized))
    func namingRule() async {
        await propertyCheck(count: 500, input: Gen.uint8().array(of: 0...44)) { picks in
            try check(picks: picks)
        }

        // A nested function rather than the closure's body: AGENTS.md, closures inside #expect
        // inside another closure.
        func check(picks: [UInt8]) throws {
            let name = String(String.UnicodeScalarView(picks.map { Self.scalars[Int($0) % Self.scalars.count] }))
            let reference = try Regex(#"^\p{L}[\p{L}\p{N}_]*$"#).matchingSemantics(.unicodeScalar)
            let matches = try reference.wholeMatch(in: name) != nil
            let isName = name.utf8.count <= 40 && matches
            let schema = EventSchema(name: "one_property", version: 1, consentCategory: .analytics, properties: [])
            let sut = GoogleAnalyticsBatchEncoder(plan: try TrackingPlan(schemas: [schema]), now: { Date(timeIntervalSince1970: 1_795_442_607) })
            let record = EventRecord(event: OneProperty(parameter: name), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
            let expected: [GoogleAnalyticsEncodingError] = isName ? [] : [.invalidParameterName(event: "one_property", parameter: name)]

            let actual = sut.requests(for: [record])

            #expect(actual.skippedRecords.map(\.reason) == expected)
            #expect(actual.requests.flatMap(\.recordIDs) == (isName ? [record.id] : []))
        }
    }
}
#endif
