import Foundation
import HTTPDestinations
import Events
import SnowplowEncoding
import Testing
import TrackingPlans

@Suite("HTTPDestination.snowplow and SnowplowBatchEncoder: setup errors")
struct SnowplowSetupErrorTests {
    @Test("The factory throws invalidCollector for a URL that isn't a plain https collector, or names the endpoint in any case, and accepts one that is", arguments: [
        ("http://collector.example.com", true), ("http://localhost:9090", true), ("ftp://collector.example.com", true),
        ("https://", true), ("https:///path", true), ("https://user@collector.example.com", true), ("https://:secret@collector.example.com", true),
        ("https://collector.example.com?x=1", true), ("https://collector.example.com#x", true),
        ("https://collector.example.com/com.snowplowanalytics.snowplow/tp2", true), ("https://collector.example.com/com.snowplowanalytics.snowplow/tp2/", true),
        ("https://collector.example.com/com.snowplowanalytics.snowplow", true), ("https://collector.example.com/TP2", true),
        ("https://collector.example.com/COM.SNOWPLOWANALYTICS.SNOWPLOW/", true), ("https://collector.example.com/i", false),
        ("https://collector.example.com/tp2x", false), ("https://collector.example.com/tp1", false),
        ("https://collector.example.com", false), ("https://collector.example.com/", false), ("https://localhost:8443", false),
        ("https://example.com/snowplow/collector", false),
    ])
    func invalidCollector(collector: String, throwsError: Bool) throws {
        let plan = try TrackingPlan(schemas: [])
        let url = try #require(URL(string: collector))
        let expected: SnowplowSetupError? = throwsError ? .invalidCollector : nil

        let actual: SnowplowSetupError?
        do {
            _ = try HTTPDestination.snowplow(collector: url, vendor: "com.example", appID: "shop", plan: plan)
            actual = nil
        } catch {
            actual = error
        }

        #expect(actual == expected)
    }

    @Test("The factory and the encoder throw invalidVendor for a vendor Iglu doesn't take, or with an empty label, and accept one that is", arguments: [
        ("", true), (".", true), ("com.", true), (".com", true), ("com..example", true), ("com example", true), ("com/example", true),
        ("com.exämple", true), ("com.example:1", true),
        ("a", false), ("acme", false), ("com.acme", false), ("com.acme-corp_1.app", false), ("COM.Acme", false), ("io.github.user-name", false),
    ])
    func invalidVendor(vendor: String, throwsError: Bool) throws {
        let plan = try TrackingPlan(schemas: [])
        let collector = try #require(URL(string: "https://collector.example.com"))
        let expected: SnowplowSetupError? = throwsError ? .invalidVendor : nil

        let actualFactory: SnowplowSetupError?
        do {
            _ = try HTTPDestination.snowplow(collector: collector, vendor: vendor, appID: "shop", plan: plan)
            actualFactory = nil
        } catch {
            actualFactory = error
        }
        let actualEncoder: SnowplowSetupError?
        do {
            _ = try SnowplowBatchEncoder(vendor: vendor, appID: "shop", plan: plan)
            actualEncoder = nil
        } catch {
            actualEncoder = error
        }

        #expect(actualFactory == expected)
        #expect(actualEncoder == expected)
    }

    // Snowplow's app_id holds 255 characters
    // (https://docs.snowplow.io/docs/fundamentals/canonical-event/), counted as a JVM string
    // counts them, in UTF-16 code units: "😀" is two.
    @Test("The encoder throws invalidAppID for an empty app ID or one past 255 UTF-16 code units, and accepts one to 255", arguments: [
        ("", true), (String(repeating: "a", count: 256), true), (String(repeating: "😀", count: 128), true),
        ("a", false), (String(repeating: "a", count: 255), false), (String(repeating: "😀", count: 127) + "a", false), (" ", false),
    ])
    func invalidAppID(appID: String, throwsError: Bool) throws {
        let plan = try TrackingPlan(schemas: [])
        let collector = try #require(URL(string: "https://collector.example.com"))
        let expected: SnowplowSetupError? = throwsError ? .invalidAppID : nil

        let actualFactory: SnowplowSetupError?
        do {
            _ = try HTTPDestination.snowplow(collector: collector, vendor: "com.example", appID: appID, plan: plan)
            actualFactory = nil
        } catch {
            actualFactory = error
        }
        let actualEncoder: SnowplowSetupError?
        do {
            _ = try SnowplowBatchEncoder(vendor: "com.example", appID: appID, plan: plan)
            actualEncoder = nil
        } catch {
            actualEncoder = error
        }

        #expect(actualFactory == expected)
        #expect(actualEncoder == expected)
    }

    @Test("The factory checks the collector before the vendor, and the vendor before the app ID")
    func order() throws {
        let plan = try TrackingPlan(schemas: [])
        let http = try #require(URL(string: "http://collector.example.com"))
        let https = try #require(URL(string: "https://collector.example.com"))

        #expect(throws: SnowplowSetupError.invalidCollector) {
            try HTTPDestination.snowplow(collector: http, vendor: "", appID: "", plan: plan)
        }
        #expect(throws: SnowplowSetupError.invalidVendor) {
            try HTTPDestination.snowplow(collector: https, vendor: "", appID: "", plan: plan)
        }
    }

    @Test("A plan holding an event Iglu can't name still sets up: only its records are skipped")
    func planWithUnnamableEvent() throws {
        let unnamable = EventSchema(name: "Order Completed", version: 1, consentCategory: .analytics, properties: [])
        let plan = try TrackingPlan(schemas: [unnamable])

        #expect(throws: Never.self) {
            try SnowplowBatchEncoder(vendor: "com.example", appID: "shop", plan: plan)
        }
    }
}
