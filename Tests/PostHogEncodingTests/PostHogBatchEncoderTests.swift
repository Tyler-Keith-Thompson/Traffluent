import EventMacros
import Foundation
import Instrumentation
import PostHogEncoding
import Sessions
import StandardContext
import Testing
import Trackers
import TrackingPlans

@Suite("PostHogBatchEncoder")
struct PostHogBatchEncoderTests {
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

    enum TraceParentKey: ServiceContextKey {
        typealias Value = String
    }

    // PostHog's batch capture request (https://posthog.com/docs/api/capture, "Batch events"):
    // {"api_key": <project token>, "batch": [{"event", "distinct_id", "properties", "timestamp"}]},
    // with each event's uuid as PostHog's SDKs send it. The first record reveals its email, which
    // still isn't sent.
    @Test("A hand-worked batch encodes to PostHog's batch capture request, byte for byte, without its Sensitive email")
    func handWorkedBatch() throws {
        let plan = try TrackingPlan(schemas: [SignedUp.schema, CheckoutStarted.schema])
        let sut = PostHogBatchEncoder(projectToken: "phc_test", plan: plan)
        var context = ServiceContext.topLevel
        context[ApplicationKey.self] = ApplicationKey.Value(bundleIdentifier: "com.example.shop", version: "2.4.1", build: "418")
        context[DeviceKey.self] = DeviceKey.Value(model: "iPhone17,1", formFactor: .phone)
        context[LocaleKey.self] = Locale(identifier: "en_US")
        context[NetworkKey.self] = .wifi
        context[OperatingSystemKey.self] = OperatingSystemKey.Value(name: "iOS", version: "26.1.0")
        context[SampleRateKey.self] = try SampleRate(0.5)
        context[SessionKey.self] = UUID(uuidString: "00000000-0000-4000-8000-00000000000A")!
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
        let expected = #"{"api_key":"phc_test","batch":[{"distinct_id":"00000000-0000-4000-8000-00000000000a","event":"signed_up","properties":{"$app_build":"418","$app_namespace":"com.example.shop","$app_version":"2.4.1","$device_model":"iPhone17,1","$device_type":"Mobile","$geoip_disable":true,"$locale":"en-US","$network_cellular":false,"$network_wifi":true,"$os_name":"iOS","$os_version":"26.1.0","$process_person_profile":false,"$session_id":"00000000-0000-4000-8000-00000000000a","discount":0.25,"plan":"pro","referrer":null,"seats":3,"tags":["beta","ios"],"trialEndsAt":"2026-12-07T14:03:27.000Z"},"timestamp":"2026-11-23T14:03:27.500Z","uuid":"6f9619ff-8b86-d011-b42d-00c04fc964ff"},{"distinct_id":"00000000-0000-4000-8000-00000000000c","event":"checkout_started","properties":{"$geoip_disable":true,"$process_person_profile":false,"$session_id":"00000000-0000-4000-8000-00000000000c","cartSize":2,"coupon":null},"timestamp":"2026-11-23T14:03:28.250Z","uuid":"00000000-0000-4000-8000-000000000002"}]}"#
        let expectedContentType = "application/json"

        let actual = try #require(sut.requests(for: [first, second]).requests.first).body

        #expect(String(decoding: actual.body, as: UTF8.self) == expected)
        #expect(actual.contentType == expectedContentType)
    }

    @Test("A redelivered record encodes with the uuid it was first sent with")
    func redelivered() throws {
        let plan = try TrackingPlan(schemas: [CheckoutStarted.schema])
        let sut = PostHogBatchEncoder(projectToken: "phc_test", plan: plan)
        var context = ServiceContext.topLevel
        context[SessionKey.self] = UUID(uuidString: "00000000-0000-4000-8000-00000000000A")!
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

    @Test("Events are encoded in the batch's order, oldest first")
    func order() throws {
        let plan = try TrackingPlan(schemas: [CheckoutStarted.schema])
        let sut = PostHogBatchEncoder(projectToken: "phc_test", plan: plan)
        var context = ServiceContext.topLevel
        context[SessionKey.self] = UUID()
        let batch = [3, 1, 2].map { size in
            EventRecord(event: CheckoutStarted(cartSize: size, coupon: nil), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil, context: context)
        }
        let expected: [Int] = [3, 1, 2]

        let body = try #require(sut.requests(for: batch).requests.first).body.body
        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let events = try #require(object["batch"] as? [[String: Any]])
        let actual = events.compactMap { ($0["properties"] as? [String: Any])?["cartSize"] as? Int }

        #expect(actual == expected)
    }

    @Test("The project token is written as given, escaped as a JSON string")
    func projectTokenEscaped() throws {
        let sut = PostHogBatchEncoder(projectToken: #"phc_"quoted"\"#, plan: try TrackingPlan(schemas: [CheckoutStarted.schema]))
        let record = EventRecord(event: CheckoutStarted(cartSize: 1, coupon: nil), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)
        let expected = #"{"api_key":"phc_\"quoted\"\\","batch":["#

        let actual = try #require(sut.requests(for: [record]).requests.first).body

        #expect(String(decoding: actual.body, as: UTF8.self).hasPrefix(expected))
    }

    @Test("A timestamp is ISO 8601 in UTC with milliseconds and a Z, whole seconds included")
    func timestamp() throws {
        let plan = try TrackingPlan(schemas: [CheckoutStarted.schema])
        let sut = PostHogBatchEncoder(projectToken: "phc_test", plan: plan)
        var context = ServiceContext.topLevel
        context[SessionKey.self] = UUID(uuidString: "00000000-0000-4000-8000-00000000000A")!
        let record = EventRecord(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
            event: CheckoutStarted(cartSize: 1, coupon: nil),
            timestamp: Date(timeIntervalSince1970: 0.125),
            sourceLocation: nil,
            context: context
        )
        let expected = #"{"api_key":"phc_test","batch":[{"distinct_id":"00000000-0000-4000-8000-00000000000a","event":"checkout_started","properties":{"$geoip_disable":true,"$process_person_profile":false,"$session_id":"00000000-0000-4000-8000-00000000000a","cartSize":1,"coupon":null},"timestamp":"1970-01-01T00:00:00.125Z","uuid":"00000000-0000-4000-8000-000000000001"}]}"#

        let actual = try #require(sut.requests(for: [record]).requests.first).body

        #expect(String(decoding: actual.body, as: UTF8.self) == expected)
    }

    @Test("A Sensitive property is left out, whether or not the record reveals it", arguments: [true, false])
    func sensitiveNeverSent(reveals: Bool) throws {
        let plan = try TrackingPlan(schemas: [SignedUp.schema])
        let sut = PostHogBatchEncoder(projectToken: "phc_test", plan: plan)
        var context = ServiceContext.topLevel
        context[SessionKey.self] = UUID()
        var record = EventRecord(
            event: SignedUp(plan: "pro", email: Sensitive("ada@example.com"), referrer: "ad", seats: 1, discount: 0, trialEndsAt: Date(timeIntervalSince1970: 0), tags: []),
            timestamp: Date(timeIntervalSince1970: 0),
            sourceLocation: nil,
            context: context
        )
        record.revealsSensitiveValues = reveals
        let expectedKeys = ["$geoip_disable", "$process_person_profile", "$session_id", "discount", "plan", "referrer", "seats", "tags", "trialEndsAt"]

        let body = try #require(sut.requests(for: [record]).requests.first).body.body
        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let event = try #require((object["batch"] as? [[String: Any]])?.first)
        let actual = try #require(event["properties"] as? [String: Any]).keys.sorted()

        #expect(actual == expectedKeys)
        #expect(!String(decoding: body, as: UTF8.self).contains("ada@example.com"))
    }
}
