import AmplitudeEncoding
import EventMacros
import Foundation
import Instrumentation
import Sessions
import StandardContext
import Testing
import Trackers
import TrackingPlans

@Suite("AmplitudeBatchEncoder")
struct AmplitudeBatchEncoderTests {
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

    enum TraceParentKey: ServiceContextKey {
        typealias Value = String
    }

    // Amplitude's HTTP V2 request (https://amplitude.com/docs/apis/analytics/http-v2):
    // {"api_key": <API key>, "events": [{"device_id", "event_type", "time" in epoch milliseconds,
    // "event_properties", "insert_id", "session_id", and the device's top-level fields}]}. The
    // first record's session is a version 7 UUID whose first 48 bits are 1795442600000; the
    // second's a version 4 one, which has no session_id. The first record reveals its email,
    // which still isn't sent.
    @Test("A hand-worked batch encodes to Amplitude's HTTP V2 request, byte for byte, without its Sensitive email")
    func handWorkedBatch() throws {
        let plan = try TrackingPlan(schemas: [SignedUp.schema, CheckoutStarted.schema])
        let sut = AmplitudeBatchEncoder(apiKey: "test-api-key", plan: plan)
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
        let expected = #"{"api_key":"test-api-key","events":[{"app_version":"2.4.1","device_id":"01a208b7-e840-7a3e-8b4d-5c6e7f801234","device_model":"iPhone17,1","event_properties":{"discount":0.25,"plan":"pro","referrer":null,"seats":3,"tags":["beta","ios"],"trialEndsAt":"2026-12-07T14:03:27.000Z"},"event_type":"signed_up","insert_id":"6f9619ff-8b86-d011-b42d-00c04fc964ff","language":"en-US","os_name":"iOS","os_version":"26.1.0","platform":"iOS","session_id":1795442600000,"time":1795442607500},{"device_id":"00000000-0000-4000-8000-00000000000c","event_properties":{"cartSize":2,"coupon":null},"event_type":"checkout_started","insert_id":"00000000-0000-4000-8000-000000000002","time":1795442608250}]}"#
        let expectedContentType = "application/json"

        let actual = try #require(sut.requests(for: [first, second]).requests.first).body

        #expect(String(decoding: actual.body, as: UTF8.self) == expected)
        #expect(actual.contentType == expectedContentType)
    }

    @Test("A redelivered record encodes with the insert_id it was first sent with")
    func redelivered() throws {
        let plan = try TrackingPlan(schemas: [CheckoutStarted.schema])
        let sut = AmplitudeBatchEncoder(apiKey: "test-api-key", plan: plan)
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

    @Test("Events are encoded in the batch's order, oldest first")
    func order() throws {
        let plan = try TrackingPlan(schemas: [CheckoutStarted.schema])
        let sut = AmplitudeBatchEncoder(apiKey: "test-api-key", plan: plan)
        var context = ServiceContext.topLevel
        context[SessionKey.self] = UUID()
        let batch = [3, 1, 2].map { size in
            EventRecord(event: CheckoutStarted(cartSize: size, coupon: nil), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil, context: context)
        }
        let expected: [Int] = [3, 1, 2]

        let body = try #require(sut.requests(for: batch).requests.first).body.body
        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let events = try #require(object["events"] as? [[String: Any]])
        let actual = events.compactMap { ($0["event_properties"] as? [String: Any])?["cartSize"] as? Int }

        #expect(actual == expected)
    }

    @Test("The API key is written as given, escaped as a JSON string")
    func apiKeyEscaped() throws {
        let sut = AmplitudeBatchEncoder(apiKey: #"key"quoted"\"#, plan: try TrackingPlan(schemas: [CheckoutStarted.schema]))
        let record = EventRecord(event: CheckoutStarted(cartSize: 1, coupon: nil), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)
        let expected = #"{"api_key":"key\"quoted\"\\","events":["#

        let actual = try #require(sut.requests(for: [record]).requests.first).body

        #expect(String(decoding: actual.body, as: UTF8.self).hasPrefix(expected))
    }

    @Test("time is the timestamp in whole milliseconds since 1970, rounded down, before 1970 included", arguments: [
        (0.125, Int64(125)), (0.0009, 0), (1_795_442_607.9999, 1_795_442_607_999), (-0.0005, -1), (-1, -1_000),
    ])
    func time(seconds: Double, expected: Int64) throws {
        let plan = try TrackingPlan(schemas: [CheckoutStarted.schema])
        let sut = AmplitudeBatchEncoder(apiKey: "test-api-key", plan: plan)
        let record = EventRecord(event: CheckoutStarted(cartSize: 1, coupon: nil), timestamp: Date(timeIntervalSince1970: seconds), sourceLocation: nil)

        let body = try #require(sut.requests(for: [record]).requests.first).body.body
        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let event = try #require((object["events"] as? [[String: Any]])?.first)
        let actual = (event["time"] as? NSNumber)?.int64Value

        #expect(actual == expected)
    }

    @Test("A Sensitive property is left out, whether or not the record reveals it", arguments: [true, false])
    func sensitiveNeverSent(reveals: Bool) throws {
        let plan = try TrackingPlan(schemas: [SignedUp.schema])
        let sut = AmplitudeBatchEncoder(apiKey: "test-api-key", plan: plan)
        var context = ServiceContext.topLevel
        context[SessionKey.self] = UUID()
        var record = EventRecord(
            event: SignedUp(plan: "pro", email: Sensitive("ada@example.com"), referrer: "ad", seats: 1, discount: 0, trialEndsAt: Date(timeIntervalSince1970: 0), tags: []),
            timestamp: Date(timeIntervalSince1970: 0),
            sourceLocation: nil,
            context: context
        )
        record.revealsSensitiveValues = reveals
        let expectedKeys = ["discount", "plan", "referrer", "seats", "tags", "trialEndsAt"]

        let body = try #require(sut.requests(for: [record]).requests.first).body.body
        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let event = try #require((object["events"] as? [[String: Any]])?.first)
        let actual = try #require(event["event_properties"] as? [String: Any]).keys.sorted()

        #expect(actual == expectedKeys)
        #expect(!String(decoding: body, as: UTF8.self).contains("ada@example.com"))
    }

    @Test("An event without properties is sent with an empty event_properties")
    func emptyProperties() throws {
        let sut = AmplitudeBatchEncoder(apiKey: "test-api-key", plan: try TrackingPlan(schemas: [Opened.schema]))
        let record = EventRecord(id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!, event: Opened(), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)
        let expected = #"{"api_key":"test-api-key","events":[{"device_id":"00000000-0000-4000-8000-000000000001","event_properties":{},"event_type":"opened","insert_id":"00000000-0000-4000-8000-000000000001","time":0}]}"#

        let actual = try #require(sut.requests(for: [record]).requests.first).body

        #expect(String(decoding: actual.body, as: UTF8.self) == expected)
    }
}
