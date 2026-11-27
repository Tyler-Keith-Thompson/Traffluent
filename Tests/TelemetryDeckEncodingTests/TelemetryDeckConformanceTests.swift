import DestinationTesting
import EventMacros
import Foundation
import HTTPDestinations
import HTTPTypes
import Instrumentation
import Sessions
import StandardContext
import TelemetryDeckEncoding
import Testing
import TrackingPlans

@Suite("HTTPDestination.telemetryDeck: conformance", .timeLimit(.minutes(1)))
struct TelemetryDeckConformanceTests {
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

    @Event(name: "Checkout.started", version: 2)
    struct CheckoutStarted {
        var cartSize: Int
        var coupon: String?
    }

    // No TelemetryDeck destination sends a Sensitive value, so there is no opted-in destination to
    // check.
    @Test("TelemetryDeck's destination keeps every rule of a vendor destination", arguments: ConformanceCheck.allCases)
    func conformance(check: ConformanceCheck) async throws {
        let sut = DestinationConformance(limit: TelemetryDeckBatchEncoder.batchLimit) { setup in
            try HTTPDestination.telemetryDeck(appID: "B97579B6-FFB8-4AC5-AAA7-DA5796CC5DCE", namespace: "com.example", testMode: false, plan: setup.plan, transport: setup.transport, backoff: setup.backoff)
        }

        try await sut.expect(check)
    }

    // The fixture is an Ingest API v3 request as https://telemetrydeck.com/docs/ingest/v3/ shows it
    // (read 2026-11-27): an array of flat events, appID, clientUser and receivedAt as strings,
    // isTestMode as "true" or "false", the parameters beside them, and the built-in ones named as
    // https://telemetrydeck.com/docs/ingest/default-parameters/ lists them, checked by hand against
    // both. The first record has the standard context and a session, the second a session alone.
    // Each clientUser is SHA256 of the lowercase session, by `shasum -a 256`:
    // "01a208b7-e840-7a3e-8b4d-5c6e7f801234" is b71ff296...3e645344, and
    // "00000000-0000-4000-8000-00000000000c" 613513e3...dc49bd67. 1,795,442,607 seconds
    // after 1970 is 2026-11-23T14:03:27Z.
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
        let sut = DestinationConformance(limit: TelemetryDeckBatchEncoder.batchLimit) { setup in
            try HTTPDestination.telemetryDeck(appID: "B97579B6-FFB8-4AC5-AAA7-DA5796CC5DCE", namespace: "com.example", testMode: true, plan: setup.plan, transport: setup.transport, backoff: setup.backoff)
        }

        try await sut.expectRequests(of: [first, second], plan: plan, matchFixture: "hand-worked-batch", subdirectory: "Fixtures", in: .module)
    }

    @Test("The destination posts JSON to the namespace's Ingest API v3 endpoint, with no other header field", arguments: [
        ("com.example", "https://nom.telemetrydeck.com/v3/com.example/"),
        ("a", "https://nom.telemetrydeck.com/v3/a/"),
        ("W", "https://nom.telemetrydeck.com/v3/W/"),
        ("Acme_Corp-2.app", "https://nom.telemetrydeck.com/v3/Acme_Corp-2.app/"),
        ("...", "https://nom.telemetrydeck.com/v3/.../"),
    ])
    func endpoint(namespace: String, expected: String) async throws {
        let plan = try TrackingPlan(schemas: [CheckoutStarted.schema])
        let record = EventRecord(event: CheckoutStarted(cartSize: 1, coupon: nil), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let transport = ScriptedTransport([.status(.ok)])
        let sut = try HTTPDestination.telemetryDeck(appID: "B97579B6-FFB8-4AC5-AAA7-DA5796CC5DCE", namespace: namespace, testMode: false, plan: plan, transport: transport)
        let expectedMethod = HTTPRequest.Method.post
        let expectedContentType = "application/json"
        let expectedFieldNames: Set<HTTPField.Name> = [.contentType]

        await sut.receive([record])

        let actual = try #require(transport.requests.first).request
        #expect(actual.url?.absoluteString == expected)
        #expect(actual.method == expectedMethod)
        #expect(actual.headerFields[.contentType] == expectedContentType)
        #expect(Set(actual.headerFields.map(\.name)) == expectedFieldNames)
    }

    @Test("A 503, TelemetryDeck's answer while its queue is full, is sent again, byte for byte, until it is taken")
    func queueFullRetried() async throws {
        let plan = try TrackingPlan(schemas: [CheckoutStarted.schema])
        let record = EventRecord(event: CheckoutStarted(cartSize: 1, coupon: nil), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let transport = ScriptedTransport([.status(.serviceUnavailable), .status(.ok)])
        let backoff = try ExponentialBackoff(initialDelay: .milliseconds(1), maximumDelay: .milliseconds(1))
        let sut = try HTTPDestination.telemetryDeck(appID: "B97579B6-FFB8-4AC5-AAA7-DA5796CC5DCE", namespace: "com.example", testMode: false, plan: plan, transport: transport, backoff: backoff)
        let expectedAttempts = 2

        await sut.receive([record])

        let bodies = transport.requests.map(\.body)
        #expect(bodies.count == expectedAttempts)
        #expect(Set(bodies).count == 1)
    }
}
