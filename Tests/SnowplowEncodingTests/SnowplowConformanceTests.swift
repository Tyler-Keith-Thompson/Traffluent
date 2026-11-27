import DestinationTesting
import EventMacros
import Foundation
import HTTPDestinations
import HTTPTypes
import Instrumentation
import Sessions
import SnowplowEncoding
import StandardContext
import Testing
import TrackingPlans

@Suite("HTTPDestination.snowplow: conformance", .timeLimit(.minutes(1)))
struct SnowplowConformanceTests {
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

    // No Snowplow destination sends a Sensitive value, so there is no opted-in destination to
    // check. The SP-Anonymous field the factory adds holds no trace context, so
    // traceContextWithheld still holds with it.
    @Test("Snowplow's destination keeps every rule of a vendor destination", arguments: ConformanceCheck.allCases)
    func conformance(check: ConformanceCheck) async throws {
        let collector = try #require(URL(string: "https://collector.example.com"))
        let sut = DestinationConformance(limit: SnowplowBatchEncoder.batchLimit) { setup in
            try HTTPDestination.snowplow(collector: collector, vendor: "com.example", appID: "shop", plan: setup.plan, transport: setup.transport, backoff: setup.backoff)
        }

        try await sut.expect(check)
    }

    // The fixture is a tracker protocol 2 request as Snowplow's example HTTP requests show it
    // (https://docs.snowplow.io/docs/events/http-requests/): payload_data 1-0-4 of self-describing
    // events, with ue_pr and co for JSON (https://docs.snowplow.io/docs/fundamentals/schemas/), the
    // atomic fields as https://docs.snowplow.io/docs/fundamentals/canonical-event/ lists them, and
    // the mobile_context 1-0-3 and application 1-0-0 entities of Iglu Central, checked by hand
    // against them: the first record has the standard context and a session, the second a session
    // alone.
    @Test("A hand-worked batch is posted as the recorded fixture, byte for byte, without its Sensitive email")
    func handWorkedFixture() async throws {
        let plan = try TrackingPlan(schemas: [SignedUp.schema, CheckoutStarted.schema])
        var context = ServiceContext.topLevel
        context[ApplicationKey.self] = ApplicationKey.Value(bundleIdentifier: "com.example.shop", version: "2.4.1", build: "418")
        context[DeviceKey.self] = DeviceKey.Value(model: "iPhone17,1", formFactor: .phone)
        context[LocaleKey.self] = Locale(identifier: "en_US")
        context[NetworkKey.self] = .cellular
        context[OperatingSystemKey.self] = OperatingSystemKey.Value(name: "iOS", version: "26.1.0")
        context[SessionKey.self] = UUID(uuidString: "01A208B7-E840-7A3E-8B4D-5C6E7F801234")!
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
        let collector = try #require(URL(string: "https://collector.example.com"))
        let sut = DestinationConformance(limit: SnowplowBatchEncoder.batchLimit) { setup in
            try HTTPDestination.snowplow(collector: collector, vendor: "com.example.shop", appID: "shop-ios", plan: setup.plan, transport: setup.transport, backoff: setup.backoff)
        }

        try await sut.expectRequests(of: [first, second], plan: plan, matchFixture: "hand-worked-batch", subdirectory: "Fixtures", in: .module)
    }

    @Test("The destination posts JSON to the collector's tp2 endpoint, after its path, with SP-Anonymous and no other header field", arguments: [
        ("https://collector.example.com", "https://collector.example.com/com.snowplowanalytics.snowplow/tp2"),
        ("https://collector.example.com/", "https://collector.example.com/com.snowplowanalytics.snowplow/tp2"),
        ("https://example.com/snowplow", "https://example.com/snowplow/com.snowplowanalytics.snowplow/tp2"),
        ("https://example.com:8443/a%2Fb//", "https://example.com:8443/a%2Fb/com.snowplowanalytics.snowplow/tp2"),
        ("HTTPS://collector.example.com", "HTTPS://collector.example.com/com.snowplowanalytics.snowplow/tp2"),
    ])
    func endpoint(collector: String, expected: String) async throws {
        let plan = try TrackingPlan(schemas: [CheckoutStarted.schema])
        let record = EventRecord(event: CheckoutStarted(cartSize: 1, coupon: nil), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let transport = ScriptedTransport([.status(.ok)])
        let sut = try HTTPDestination.snowplow(collector: try #require(URL(string: collector)), vendor: "com.example", appID: "shop", plan: plan, transport: transport)
        let expectedMethod = HTTPRequest.Method.post
        let expectedContentType = "application/json"
        let expectedAnonymous = "*"
        let anonymous = try #require(HTTPField.Name("SP-Anonymous"))
        let expectedFieldNames: Set<HTTPField.Name> = [.contentType, anonymous]

        await sut.receive([record])

        let actual = try #require(transport.requests.first).request
        #expect(actual.url?.absoluteString == expected)
        #expect(actual.method == expectedMethod)
        #expect(actual.headerFields[.contentType] == expectedContentType)
        #expect(actual.headerFields[anonymous] == expectedAnonymous)
        #expect(Set(actual.headerFields.map(\.name)) == expectedFieldNames)
    }

    @Test("A batch of more events than a request holds is posted as several requests, each with SP-Anonymous")
    func everyRequestAnonymous() async throws {
        let plan = try TrackingPlan(schemas: [CheckoutStarted.schema])
        let batch = (0..<26).map { index in
            EventRecord(event: CheckoutStarted(cartSize: index, coupon: nil), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        }
        let transport = ScriptedTransport([.status(.ok)])
        let collector = try #require(URL(string: "https://collector.example.com"))
        let sut = try HTTPDestination.snowplow(collector: collector, vendor: "com.example", appID: "shop", plan: plan, transport: transport)
        let anonymous = try #require(HTTPField.Name("SP-Anonymous"))
        let expected: [String?] = ["*", "*"]

        await sut.receive(batch)

        let actual = transport.requests.map { $0.request.headerFields[anonymous] }
        #expect(actual == expected)
    }
}
