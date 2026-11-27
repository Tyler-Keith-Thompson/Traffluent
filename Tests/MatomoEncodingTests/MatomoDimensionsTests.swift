import EventMacros
import Foundation
import HTTPDestinations
import MatomoEncoding
import PropertyBased
import Testing
import TrackingPlans
import TraffluentTestSupport

// Matomo reads dimension<ID> as the value of the custom dimension of that ID
// (https://developer.matomo.org/api-reference/tracking-api, "dimension[0-999]", read 2026-11-27),
// and each tracking request of a bulk request through PHP's parse_url and parse_str
// (plugins/BulkTracking/Tracker/Requests.php, matomo-org/matomo 6.0.0), which reads `+` as a space
// and `%XX` as a byte.
@Suite("MatomoBatchEncoder: dimensions")
struct MatomoDimensionsTests {
    struct Cart: Codable, Hashable {
        var size: Int
        var currency: String
    }

    @Event(name: "signed_up")
    struct SignedUp {
        var plan: String
        var seats: Int
        var discount: Double
        var trial: Bool
        var tags: [String]
        var cart: Cart
        var referrer: String?
        var email: Sensitive<String>
        var note: String
    }

    @Event(name: "noted")
    struct Noted {
        var text: String
    }

    @Test("Each mapped property is its dimension: a string as it is, a number as JSON writes it, a Boolean as true or false, an array or object as its JSON, from the lowest dimension to the highest; nil and an unmapped property, Sensitive or not, are left out")
    func values() throws {
        let plan = try TrackingPlan(schemas: [SignedUp.schema])
        let sut = try MatomoBatchEncoder(siteID: 1, dimensions: ["plan": 9, "seats": 2, "discount": 30, "trial": 4, "tags": 5, "cart": 1, "referrer": 7], category: "Shop", plan: plan, now: { Date(timeIntervalSince1970: 1_795_442_607) })
        var record = EventRecord(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!,
            event: SignedUp(plan: "pro plus", seats: 3, discount: 0.25, trial: true, tags: ["beta", "ios"], cart: Cart(size: 2, currency: "EUR"), referrer: nil, email: Sensitive("ada@example.com"), note: "unmapped"),
            timestamp: Date(timeIntervalSince1970: 1_795_442_607),
            sourceLocation: nil
        )
        record.revealsSensitiveValues = true
        let expected = #"{"requests":["?idsite=1&rec=1&apiv=1&_id=8000000000000002&cdt=1795442607&ca=1&e_c=Shop&e_a=signed_up&dimension1=%7B%22currency%22%3A%22EUR%22%2C%22size%22%3A2%7D&dimension2=3&dimension4=true&dimension5=%5B%22beta%22%2C%22ios%22%5D&dimension9=pro%20plus&dimension30=0.25"]}"#

        let actual = sut.requests(for: [record])

        #expect(actual.skippedRecords.isEmpty)
        let actualBodies = actual.requests.map { String(decoding: $0.body.body, as: UTF8.self) }
        #expect(actualBodies == [expected])
    }

    @Test("Every character of a value but a letter, digit, -, ., _ and ~ is percent-encoded, so no value can end its parameter or read back as anything else", arguments: [
        ("aZ09-._~", "aZ09-._~"), ("a&b=c", "a%26b%3Dc"), ("a+b", "a%2Bb"), ("a b", "a%20b"), ("a#b", "a%23b"), ("a/b?c", "a%2Fb%3Fc"),
        ("a%b", "a%25b"), ("é", "%C3%A9"), ("\"\\", "%22%5C"), ("😀", "%F0%9F%98%80"), ("a\nb", "a%0Ab"),
    ])
    func percentEncoded(value: String, expected: String) throws {
        let sut = try MatomoBatchEncoder(siteID: 1, dimensions: ["text": 1], category: value, plan: try TrackingPlan(schemas: [Noted.schema]), now: { Date(timeIntervalSince1970: 1_795_442_607) })
        let record = EventRecord(id: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!, event: Noted(text: value), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expectedBody = #"{"requests":["?idsite=1&rec=1&apiv=1&_id=8000000000000002&cdt=1795442607&ca=1&e_c="# + expected + #"&e_a=noted&dimension1="# + expected + #""]}"#

        let actual = sut.requests(for: [record])

        let actualBodies = actual.requests.map { String(decoding: $0.body.body, as: UTF8.self) }
        #expect(actualBodies == [expectedBody])
    }

    // Any Unicode scalar, control characters and quotes included; surrogates are skipped.
    @Test("Any value is sent as unreserved characters and percent escapes alone, which decode to the value", .tags(.randomized))
    func percentEncodingRoundTrip() async {
        await propertyCheck(count: 500, input: Gen.uint32().array(of: 0 ... 40)) { scalars in
            try check(scalars: scalars)
        }

        // A nested function rather than the closure's body: AGENTS.md, closures inside #expect
        // inside another closure.
        func check(scalars: [UInt32]) throws {
            let text = String(String.UnicodeScalarView(scalars.compactMap { Unicode.Scalar($0 % 0x11_0000) }))
            let sut = try MatomoBatchEncoder(siteID: 1, dimensions: ["text": 1], category: "Shop", plan: try TrackingPlan(schemas: [Noted.schema]), now: { Date(timeIntervalSince1970: 1_795_442_607) })
            let record = EventRecord(event: Noted(text: text), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
            let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~%".unicodeScalars)

            let actual = sut.requests(for: [record])

            let body = try #require(actual.requests.first).body.body
            let requests = try #require(try JSONSerialization.jsonObject(with: body) as? [String: [String]])["requests"] ?? []
            let query = try #require(requests.first)
            let encoded = try #require(query.split(separator: "&").first { $0.hasPrefix("dimension1=") }).dropFirst("dimension1=".count)
            #expect(encoded.unicodeScalars.allSatisfy(allowed.contains))
            #expect(String(encoded).removingPercentEncoding == text)
        }
    }

    // Letters, the characters Matomo escapes or removes, the ones PHP's trim removes, and ones of
    // two and four bytes of UTF-8, in values of up to 100 of them: up to 600 characters as Matomo
    // stores them, either side of 250.
    static let scalars: [Unicode.Scalar] = ["a", "é", "😀", "&", "<", ">", "\"", "'", " ", "\t", "\u{0B}", "\n", "\r", "\0"]

    @Test("A dimension's value is sent exactly when Matomo stores at most 250 characters of it, as a naive reference counts them", .tags(.randomized))
    func dimensionLengthRule() async {
        await propertyCheck(count: 500, input: Gen.uint8().array(of: 0 ... 100)) { picks in
            try check(picks: picks)
        }

        // A nested function rather than the closure's body: AGENTS.md, closures inside #expect
        // inside another closure.
        func check(picks: [UInt8]) throws {
            let text = String(String.UnicodeScalarView(picks.map { Self.scalars[Int($0) % Self.scalars.count] }))
            let sut = try MatomoBatchEncoder(siteID: 1, dimensions: ["text": 1], category: "Shop", plan: try TrackingPlan(schemas: [Noted.schema]), now: { Date(timeIntervalSince1970: 1_795_442_607) })
            let record = EventRecord(event: Noted(text: text), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
            // The naive reference of how Matomo stores a value: line breaks and NULs removed, the
            // five characters HTML escapes as their entities, then PHP's trim.
            let escaped = text
                .replacingOccurrences(of: "\n", with: "")
                .replacingOccurrences(of: "\r", with: "")
                .replacingOccurrences(of: "\0", with: "")
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\"", with: "&quot;")
                .replacingOccurrences(of: "'", with: "&#039;")
            let length = escaped.trimmingCharacters(in: CharacterSet(charactersIn: " \t\u{0B}")).unicodeScalars.count
            let expected: [MatomoEncodingError] = length > 250 ? [.dimensionValueTooLong(event: "noted", property: "text", dimension: 1, length: length)] : []

            let actual = sut.requests(for: [record])

            #expect(actual.skippedRecords.map(\.reason) == expected)
            let expectedSent: [UUID] = length > 250 ? [] : [record.id]
            let actualSent = actual.requests.flatMap(\.recordIDs)
            #expect(actualSent == expectedSent)
        }
    }

    @Test("unmappedProperties lists each property of the plan no mapping names, in the plan's order, and nothing when every one is mapped")
    func unmappedProperties() throws {
        let plan = try TrackingPlan(schemas: [SignedUp.schema, Noted.schema])
        let dimensions: MatomoDimensions = ["plan": 1, "seats": 2, "discount": 3, "trial": 4, "tags": 5, "cart": 6, "referrer": 7]
        let everything: MatomoDimensions = ["plan": 1, "seats": 2, "discount": 3, "trial": 4, "tags": 5, "cart": 6, "referrer": 7, "email": 8, "note": 9, "text": 10]
        let expected = [
            MatomoUnmappedProperty(event: "noted", version: 1, property: "text"),
            MatomoUnmappedProperty(event: "signed_up", version: 1, property: "email"),
            MatomoUnmappedProperty(event: "signed_up", version: 1, property: "note"),
        ]
        let expectedNone: [MatomoUnmappedProperty] = []

        let actual = dimensions.unmappedProperties(in: plan)
        let actualNone = everything.unmappedProperties(in: plan)

        #expect(actual == expected)
        #expect(actualNone == expectedNone)
    }

    @Test("A record is sent without the properties no dimension is mapped to, rather than left out")
    func unmappedPropertiesSent() throws {
        let sut = try MatomoBatchEncoder(siteID: 1, dimensions: [:], category: "Shop", plan: try TrackingPlan(schemas: [Noted.schema]), now: { Date(timeIntervalSince1970: 1_795_442_607) })
        let record = EventRecord(id: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!, event: Noted(text: String(repeating: "a", count: 1000)), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expected = #"{"requests":["?idsite=1&rec=1&apiv=1&_id=8000000000000002&cdt=1795442607&ca=1&e_c=Shop&e_a=noted"]}"#

        let actual = sut.requests(for: [record])

        #expect(actual.skippedRecords.isEmpty)
        let actualBodies = actual.requests.map { String(decoding: $0.body.body, as: UTF8.self) }
        #expect(actualBodies == [expected])
    }

    @Test("A dictionary of dimensions maps as its literal does")
    func dictionary() throws {
        let plan = try TrackingPlan(schemas: [Noted.schema])
        let sut = try MatomoBatchEncoder(siteID: 1, dimensions: MatomoDimensions(["text": 12]), category: "Shop", plan: plan, now: { Date(timeIntervalSince1970: 1_795_442_607) })
        let record = EventRecord(id: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!, event: Noted(text: "hi"), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expected = #"{"requests":["?idsite=1&rec=1&apiv=1&_id=8000000000000002&cdt=1795442607&ca=1&e_c=Shop&e_a=noted&dimension12=hi"]}"#

        let actual = sut.requests(for: [record])

        let actualBodies = actual.requests.map { String(decoding: $0.body.body, as: UTF8.self) }
        #expect(actualBodies == [expected])
    }

    @Test("cdt is the record's time in whole seconds since 1970, rounded down, before 1970 too", arguments: [
        (1_795_442_607.999, "1795442607"), (1_795_442_607, "1795442607"), (-0.5, "-1"), (-1, "-1"), (0, "0"),
    ])
    func cdt(seconds: Double, expected: String) throws {
        let sut = try MatomoBatchEncoder(siteID: 1, dimensions: [:], category: "Shop", plan: try TrackingPlan(schemas: [Noted.schema]), now: { Date(timeIntervalSince1970: seconds) })
        let record = EventRecord(id: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!, event: Noted(text: ""), timestamp: Date(timeIntervalSince1970: seconds), sourceLocation: nil)
        let expectedBody = #"{"requests":["?idsite=1&rec=1&apiv=1&_id=8000000000000002&cdt="# + expected + #"&ca=1&e_c=Shop&e_a=noted"]}"#

        let actual = sut.requests(for: [record])

        let actualBodies = actual.requests.map { String(decoding: $0.body.body, as: UTF8.self) }
        #expect(actualBodies == [expectedBody])
    }
}
