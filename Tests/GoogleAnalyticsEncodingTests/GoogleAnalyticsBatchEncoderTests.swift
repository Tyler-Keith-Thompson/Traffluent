// The module is compiled for macOS and Linux alone (Sources/GoogleAnalyticsEncoding).
#if os(macOS) || os(Linux)
import EventMacros
import Foundation
import GoogleAnalyticsEncoding
import Instrumentation
import Sessions
import StandardContext
import Testing
import Trackers
import TrackingPlans

@Suite("GoogleAnalyticsBatchEncoder")
struct GoogleAnalyticsBatchEncoderTests {
    @Event(name: "signed_up")
    struct SignedUp {
        var plan: String
        var email: Sensitive<String>
        var referrer: String?
        var seats: Int
        var discount: Double
        var trialEndsAt: Date
        var tags: [String]
    }

    @Event(name: "checkout_started", version: 2)
    struct CheckoutStarted {
        var cartSize: Int
        var coupon: String?
    }

    @Event(name: "opened")
    struct Opened {}

    struct Cart: Codable, Hashable {
        var size: Int
        var gift: Bool
        var items: [String]
    }

    @Event(name: "cart_viewed")
    struct CartViewed {
        var cart: Cart
        var empty: [Int]
        var sensitiveTags: [Sensitive<String>]
    }

    enum TraceParentKey: ServiceContextKey {
        typealias Value = String
    }

    // The Measurement Protocol's request
    // (https://developers.google.com/analytics/devguides/collection/protocol/ga4/reference,
    // "JSON POST body"): {"client_id", "consent", "events": [{"name", "params",
    // "timestamp_micros"}]}, one client a request. The first record reveals its email, which still
    // isn't sent, and has the standard context, which isn't sent either; its session is a version 7
    // UUID whose first 48 bits are 1,795,442,600,000 ms. The second's session is a version 4 UUID,
    // so it has no session_id, and its own request.
    @Test("A hand-worked batch encodes to the Measurement Protocol's requests, a client's each, byte for byte, without its Sensitive email or its context")
    func handWorkedBatch() throws {
        let plan = try TrackingPlan(schemas: [SignedUp.schema, CheckoutStarted.schema])
        let sut = GoogleAnalyticsBatchEncoder(plan: plan, now: { Date(timeIntervalSince1970: 1_795_442_700) })
        var context = ServiceContext.topLevel
        context[ApplicationKey.self] = ApplicationKey.Value(bundleIdentifier: "com.example.shop", version: "2.4.1", build: "418")
        context[DeviceKey.self] = DeviceKey.Value(model: "iPhone17,1", formFactor: .phone)
        context[LocaleKey.self] = Locale(identifier: "en_US")
        context[NetworkKey.self] = .wifi
        context[OperatingSystemKey.self] = OperatingSystemKey.Value(name: "iOS", version: "26.1.0")
        context[SampleRateKey.self] = try SampleRate(0.5)
        context[SessionKey.self] = UUID(uuidString: "01A208B7-E840-7A3E-8B4D-5C6E7F801234")!
        context[VendorIdentifierKey.self] = Sensitive(UUID(uuidString: "00000000-0000-4000-8000-00000000000B")!)
        context[TraceParentKey.self] = "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
        let signedUp = SignedUp(
            plan: "pro",
            email: Sensitive("ada@example.com"),
            referrer: nil,
            seats: 3,
            discount: 0.25,
            trialEndsAt: Date(timeIntervalSince1970: 1_796_652_207),
            tags: ["beta", "ios"]
        )
        var first = EventRecord(
            id: UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!,
            event: signedUp,
            timestamp: Date(timeIntervalSince1970: 1_795_442_607.5),
            sourceLocation: nil,
            context: context
        )
        first.revealsSensitiveValues = true
        var secondContext = ServiceContext.topLevel
        secondContext[SessionKey.self] = UUID(uuidString: "00000000-0000-4000-8000-00000000000C")!
        let second = EventRecord(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!,
            event: CheckoutStarted(cartSize: 2, coupon: nil),
            timestamp: Date(timeIntervalSince1970: 1_795_442_608.25),
            sourceLocation: nil,
            context: secondContext,
            isRedelivered: true
        )
        let expected = [
            #"{"client_id":"117666126233631294.10037780774133961268","consent":{"ad_personalization":"DENIED","ad_user_data":"DENIED"},"events":[{"name":"signed_up","params":{"discount":0.25,"plan":"pro","seats":3,"session_id":1795442600000,"tags_0":"beta","tags_1":"ios","trialEndsAt":"2026-12-07T14:03:27.000Z"},"timestamp_micros":1795442607500000}]}"#,
            #"{"client_id":"16384.9223372036854775820","consent":{"ad_personalization":"DENIED","ad_user_data":"DENIED"},"events":[{"name":"checkout_started","params":{"cartSize":2},"timestamp_micros":1795442608250000}]}"#,
        ]
        let expectedContentType = "application/json"

        let actual = sut.requests(for: [first, second])

        #expect(actual.requests.map { String(decoding: $0.body.body, as: UTF8.self) } == expected)
        #expect(actual.requests.map(\.recordIDs) == [[first.id], [second.id]])
        #expect(actual.requests.allSatisfy { $0.body.contentType == expectedContentType })
        #expect(actual.skippedRecords.isEmpty)
    }

    @Test("A redelivered record encodes as it was first sent")
    func redelivered() throws {
        let plan = try TrackingPlan(schemas: [CheckoutStarted.schema])
        let sut = GoogleAnalyticsBatchEncoder(plan: plan, now: { Date(timeIntervalSince1970: 1_795_442_700) })
        var context = ServiceContext.topLevel
        context[SessionKey.self] = UUID(uuidString: "01A208B7-E840-7A3E-8B4D-5C6E7F801234")!
        let firstDelivery = EventRecord(
            id: UUID(uuidString: "2B4C6D8E-1A3F-4B5C-9D7E-0F1A2B3C4D5E")!,
            event: CheckoutStarted(cartSize: 1, coupon: "SPRING"),
            timestamp: Date(timeIntervalSince1970: 1_795_442_607),
            sourceLocation: nil,
            context: context
        )
        // As a delivery hands it over again: the same identifier, marked redelivered.
        let redelivery = EventRecord(
            id: firstDelivery.id,
            event: firstDelivery.event,
            timestamp: firstDelivery.timestamp,
            sourceLocation: nil,
            context: context,
            isRedelivered: true
        )
        let expected = try #require(sut.requests(for: [firstDelivery]).requests.first).body

        let actual = try #require(sut.requests(for: [redelivery]).requests.first).body

        #expect(actual == expected)
    }

    @Test("A client's events are encoded in the batch's order, oldest first")
    func order() throws {
        let plan = try TrackingPlan(schemas: [CheckoutStarted.schema])
        let sut = GoogleAnalyticsBatchEncoder(plan: plan, now: { Date(timeIntervalSince1970: 1_795_442_700) })
        var context = ServiceContext.topLevel
        context[SessionKey.self] = UUID()
        let batch = [3, 1, 2].map { size in
            EventRecord(event: CheckoutStarted(cartSize: size, coupon: nil), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil, context: context)
        }
        let expected: [Int] = [3, 1, 2]

        let body = try #require(sut.requests(for: batch).requests.first).body.body
        let request = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let events = try #require(request["events"] as? [[String: Any]])
        let actual = events.compactMap { ($0["params"] as? [String: Any])?["cartSize"] as? Int }

        #expect(actual == expected)
    }

    @Test("timestamp_micros is the timestamp in whole microseconds since 1970, rounded down", arguments: [
        (1_795_442_607.0, Int64(1_795_442_607_000_000)), (1_795_442_607.5, 1_795_442_607_500_000), (1_795_442_607.25, 1_795_442_607_250_000), (1_795_442_607.000_000_4, 1_795_442_607_000_000),
    ])
    func timestampMicros(seconds: Double, expected: Int64) throws {
        let plan = try TrackingPlan(schemas: [CheckoutStarted.schema])
        let sut = GoogleAnalyticsBatchEncoder(plan: plan, now: { Date(timeIntervalSince1970: 1_795_442_700) })
        let record = EventRecord(event: CheckoutStarted(cartSize: 1, coupon: nil), timestamp: Date(timeIntervalSince1970: seconds), sourceLocation: nil)

        let body = try #require(sut.requests(for: [record]).requests.first).body.body
        let request = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let event = try #require((request["events"] as? [[String: Any]])?.first)
        let actual = (event["timestamp_micros"] as? NSNumber)?.int64Value

        #expect(actual == expected)
    }

    @Test("A Sensitive property is left out, whether or not the record reveals it", arguments: [true, false])
    func sensitiveNeverSent(reveals: Bool) throws {
        let plan = try TrackingPlan(schemas: [SignedUp.schema])
        let sut = GoogleAnalyticsBatchEncoder(plan: plan, now: { Date(timeIntervalSince1970: 1_795_442_700) })
        var record = EventRecord(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
            event: SignedUp(plan: "pro", email: Sensitive("ada@example.com"), referrer: "ad", seats: 1, discount: 0, trialEndsAt: Date(timeIntervalSince1970: 0), tags: []),
            timestamp: Date(timeIntervalSince1970: 1_795_442_607),
            sourceLocation: nil
        )
        record.revealsSensitiveValues = reveals
        let expectedKeys = ["discount", "plan", "referrer", "seats", "trialEndsAt"]

        let body = try #require(sut.requests(for: [record]).requests.first).body.body
        let request = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let event = try #require((request["events"] as? [[String: Any]])?.first)
        let actual = try #require(event["params"] as? [String: Any]).keys.sorted()

        #expect(actual == expectedKeys)
        #expect(!String(decoding: body, as: UTF8.self).contains("ada@example.com"))
    }

    @Test("An object or array is spread into a parameter per value, named by its path joined by _, and a null, an empty array and a redacted element are left out")
    func nestedValuesFlattened() throws {
        let plan = try TrackingPlan(schemas: [CartViewed.schema])
        let sut = GoogleAnalyticsBatchEncoder(plan: plan, now: { Date(timeIntervalSince1970: 1_795_442_700) })
        var record = EventRecord(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
            event: CartViewed(cart: Cart(size: 2, gift: true, items: ["tote", "mug"]), empty: [], sensitiveTags: [Sensitive("vip")]),
            timestamp: Date(timeIntervalSince1970: 1_795_442_607),
            sourceLocation: nil
        )
        record.revealsSensitiveValues = true
        let expected = #"{"client_id":"16384.9223372036854775809","consent":{"ad_personalization":"DENIED","ad_user_data":"DENIED"},"events":[{"name":"cart_viewed","params":{"cart_gift":true,"cart_items_0":"tote","cart_items_1":"mug","cart_size":2},"timestamp_micros":1795442607000000}]}"#

        let actual = sut.requests(for: [record])

        #expect(actual.requests.map { String(decoding: $0.body.body, as: UTF8.self) } == [expected])
        #expect(actual.skippedRecords.isEmpty)
    }

    @Test("An event without properties is sent with empty params")
    func emptyProperties() throws {
        let sut = GoogleAnalyticsBatchEncoder(plan: try TrackingPlan(schemas: [Opened.schema]), now: { Date(timeIntervalSince1970: 1_795_442_700) })
        let record = EventRecord(id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!, event: Opened(), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expected = #"{"client_id":"16384.9223372036854775809","consent":{"ad_personalization":"DENIED","ad_user_data":"DENIED"},"events":[{"name":"opened","params":{},"timestamp_micros":1795442607000000}]}"#

        let actual = try #require(sut.requests(for: [record]).requests.first).body

        #expect(String(decoding: actual.body, as: UTF8.self) == expected)
    }

    @Test("Every request denies ad consent, with or without a session")
    func adConsentDenied() throws {
        let sut = GoogleAnalyticsBatchEncoder(plan: try TrackingPlan(schemas: [Opened.schema]), now: { Date(timeIntervalSince1970: 1_795_442_700) })
        var context = ServiceContext.topLevel
        context[SessionKey.self] = UUID(uuidString: "00000000-0000-4000-8000-00000000000A")!
        let batch = [
            EventRecord(event: Opened(), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil, context: context),
            EventRecord(event: Opened(), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil),
        ]
        let expected: [[String: String]?] = [["ad_personalization": "DENIED", "ad_user_data": "DENIED"], ["ad_personalization": "DENIED", "ad_user_data": "DENIED"]]

        let requests = sut.requests(for: batch).requests

        let actual = try requests.map { try (JSONSerialization.jsonObject(with: $0.body.body) as? [String: Any])?["consent"] as? [String: String] }
        #expect(actual == expected)
    }
}
#endif
