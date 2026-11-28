import EventMacros
import Foundation
import Instrumentation
import MixpanelEncoding
import Sessions
import StandardContext
import Testing
import Trackers
import TrackingPlans

// Private: its events share their names with other events of this test target, and @Event
// leaves a private type's events out of the link check of names (DefiningEvents, Limits).
@Suite("MixpanelBatchEncoder")
private struct MixpanelBatchEncoderTests {
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

    // Mixpanel's track request (https://developer.mixpanel.com/reference/track-event): a JSON
    // array of {"event", "properties": {"token", "time" in epoch milliseconds, "distinct_id",
    // "$insert_id", and the event's and default properties}}. The first record reveals its email,
    // which still isn't sent; the second has a session but no standard context.
    @Test("A hand-worked batch encodes to Mixpanel's track request, byte for byte, without its Sensitive email")
    func handWorkedBatch() throws {
        let plan = try TrackingPlan(schemas: [SignedUp.schema, CheckoutStarted.schema])
        let sut = MixpanelBatchEncoder(projectToken: "testprojecttoken", plan: plan, now: { Date(timeIntervalSince1970: 1_795_442_607) })
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
        let expected = #"[{"event":"signed_up","properties":{"$app_build_number":"418","$app_version_string":"2.4.1","$device_id":"01a208b7-e840-7a3e-8b4d-5c6e7f801234","$insert_id":"6f9619ff-8b86-d011-b42d-00c04fc964ff","$model":"iPhone17,1","$os":"iOS","$os_version":"26.1.0","$wifi":true,"discount":0.25,"distinct_id":"01a208b7-e840-7a3e-8b4d-5c6e7f801234","ip":"0","plan":"pro","referrer":null,"seats":3,"tags":["beta","ios"],"time":1795442607500,"token":"testprojecttoken","trialEndsAt":"2026-12-07T14:03:27.000Z"}},{"event":"checkout_started","properties":{"$device_id":"00000000-0000-4000-8000-00000000000c","$insert_id":"00000000-0000-4000-8000-000000000002","cartSize":2,"coupon":null,"distinct_id":"00000000-0000-4000-8000-00000000000c","ip":"0","time":1795442608250,"token":"testprojecttoken"}}]"#
        let expectedContentType = "application/json"

        let actual = try #require(sut.requests(for: [first, second]).requests.first).body

        #expect(String(decoding: actual.body, as: UTF8.self) == expected)
        #expect(actual.contentType == expectedContentType)
    }

    @Test("A redelivered record encodes with the $insert_id it was first sent with")
    func redelivered() throws {
        let plan = try TrackingPlan(schemas: [CheckoutStarted.schema])
        let sut = MixpanelBatchEncoder(projectToken: "testprojecttoken", plan: plan, now: { Date(timeIntervalSince1970: 1_795_442_607) })
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
        let sut = MixpanelBatchEncoder(projectToken: "testprojecttoken", plan: plan, now: { Date(timeIntervalSince1970: 1_795_442_607) })
        var context = ServiceContext.topLevel
        context[SessionKey.self] = UUID()
        let batch = [3, 1, 2].map { size in
            EventRecord(event: CheckoutStarted(cartSize: size, coupon: nil), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil, context: context)
        }
        let expected: [Int] = [3, 1, 2]

        let body = try #require(sut.requests(for: batch).requests.first).body.body
        let events = try #require(try JSONSerialization.jsonObject(with: body) as? [[String: Any]])
        let actual = events.compactMap { ($0["properties"] as? [String: Any])?["cartSize"] as? Int }

        #expect(actual == expected)
    }

    @Test("The project token is written into each event as given, escaped as a JSON string")
    func projectTokenEscaped() throws {
        let sut = MixpanelBatchEncoder(projectToken: #"token"quoted"\"#, plan: try TrackingPlan(schemas: [CheckoutStarted.schema]), now: { Date(timeIntervalSince1970: 1_795_442_607) })
        let batch = (0 ..< 2).map { index in
            EventRecord(event: CheckoutStarted(cartSize: index, coupon: nil), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        }
        let expectedSuffix = #","token":"token\"quoted\"\\"}}"#
        let expectedTokens: [String?] = [#"token"quoted"\"#, #"token"quoted"\"#]

        let body = try #require(sut.requests(for: batch).requests.first).body.body
        let text = String(decoding: body, as: UTF8.self)
        let events = try #require(try JSONSerialization.jsonObject(with: body) as? [[String: Any]])
        let actual = events.map { ($0["properties"] as? [String: Any])?["token"] as? String }

        #expect(text.hasSuffix(expectedSuffix + "]"))
        #expect(actual == expectedTokens)
    }

    @Test("time is the timestamp in whole milliseconds since 1970, rounded down, from 1971-01-01 on", arguments: [
        (31_536_000.0, Int64(31_536_000_000)), (31_536_000.0009, 31_536_000_000), (31_536_000.125, 31_536_000_125), (1_795_442_607.9999, 1_795_442_607_999),
    ])
    func time(seconds: Double, expected: Int64) throws {
        let plan = try TrackingPlan(schemas: [CheckoutStarted.schema])
        // The encoder's clock reads the record's own time, so the 119 hours don't decide.
        let sut = MixpanelBatchEncoder(projectToken: "testprojecttoken", plan: plan, now: { Date(timeIntervalSince1970: seconds) })
        let record = EventRecord(event: CheckoutStarted(cartSize: 1, coupon: nil), timestamp: Date(timeIntervalSince1970: seconds), sourceLocation: nil)

        let body = try #require(sut.requests(for: [record]).requests.first).body.body
        let event = try #require((try JSONSerialization.jsonObject(with: body) as? [[String: Any]])?.first)
        let actual = ((event["properties"] as? [String: Any])?["time"] as? NSNumber)?.int64Value

        #expect(actual == expected)
    }

    @Test("A Sensitive property is left out, whether or not the record reveals it", arguments: [true, false])
    func sensitiveNeverSent(reveals: Bool) throws {
        let plan = try TrackingPlan(schemas: [SignedUp.schema])
        let sut = MixpanelBatchEncoder(projectToken: "testprojecttoken", plan: plan, now: { Date(timeIntervalSince1970: 1_795_442_607) })
        var context = ServiceContext.topLevel
        context[SessionKey.self] = UUID(uuidString: "00000000-0000-4000-8000-00000000000A")!
        var record = EventRecord(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
            event: SignedUp(plan: "pro", email: Sensitive("ada@example.com"), referrer: "ad", seats: 1, discount: 0, trialEndsAt: Date(timeIntervalSince1970: 0), tags: []),
            timestamp: Date(timeIntervalSince1970: 1_795_442_607),
            sourceLocation: nil,
            context: context
        )
        record.revealsSensitiveValues = reveals
        let expectedKeys = ["$device_id", "$insert_id", "discount", "distinct_id", "ip", "plan", "referrer", "seats", "tags", "time", "token", "trialEndsAt"]

        let body = try #require(sut.requests(for: [record]).requests.first).body.body
        let event = try #require((try JSONSerialization.jsonObject(with: body) as? [[String: Any]])?.first)
        let actual = try #require(event["properties"] as? [String: Any]).keys.sorted()

        #expect(actual == expectedKeys)
        #expect(!String(decoding: body, as: UTF8.self).contains("ada@example.com"))
    }

    @Test("An event without properties is sent with only the members the encoder writes")
    func emptyProperties() throws {
        let sut = MixpanelBatchEncoder(projectToken: "testprojecttoken", plan: try TrackingPlan(schemas: [Opened.schema]), now: { Date(timeIntervalSince1970: 1_795_442_607) })
        let record = EventRecord(id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!, event: Opened(), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expected = #"[{"event":"opened","properties":{"$insert_id":"00000000-0000-4000-8000-000000000001","distinct_id":"00000000-0000-4000-8000-000000000001","ip":"0","time":1795442607000,"token":"testprojecttoken"}}]"#

        let actual = try #require(sut.requests(for: [record]).requests.first).body

        #expect(String(decoding: actual.body, as: UTF8.self) == expected)
    }
}
