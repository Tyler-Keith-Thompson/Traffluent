// The factory is compiled for macOS and Linux alone (HTTPDestination+GoogleAnalytics.swift).
#if os(macOS) || os(Linux)
import DestinationTesting
import EventMacros
import Foundation
import GoogleAnalyticsEncoding
import HTTPDestinations
import HTTPTypes
import Instrumentation
import Sessions
import StandardContext
import Testing
import TrackingPlans

// Private: its events share their names with other events of this test target, and @Event
// leaves a private type's events out of the link check of names (DefiningEvents, Limits).
@Suite("HTTPDestination.googleAnalytics: conformance", .timeLimit(.minutes(1)))
private struct GoogleAnalyticsConformanceTests {
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

    // Google Analytics never receives a Sensitive value, so there is no opted-in destination to
    // check. The kit's records are stamped at setup.timestamp, which the encoder takes as the time
    // each batch is encoded, so none falls outside the Measurement Protocol's window.
    @Test("The Google Analytics destination keeps every rule of a vendor destination, in every region", arguments: ConformanceCheck.allCases, [GoogleAnalyticsRegion.global, .eu])
    func conformance(check: ConformanceCheck, region: GoogleAnalyticsRegion) async throws {
        let sut = DestinationConformance(limit: GoogleAnalyticsBatchEncoder.batchLimit) { setup in
            try HTTPDestination.googleAnalytics(
                measurementID: "G-TEST000000",
                apiSecret: "testapisecret",
                region: region,
                plan: setup.plan,
                transport: setup.transport,
                backoff: setup.backoff,
                now: { setup.timestamp }
            )
        }

        try await sut.expect(check)
    }

    // The fixture is the request of the Measurement Protocol's reference
    // (https://developers.google.com/analytics/devguides/collection/protocol/ga4/reference, "JSON
    // POST body", read on 2026-11-27), checked by hand against it and accepted with no validation
    // message by its validation server, /debug/mp/collect, with its timestamps moved to that day:
    // the first record has the standard context and a version 7 session, the second a version 4
    // session, so each is a request of its own.
    @Test("A hand-worked batch is posted as the recorded fixture, byte for byte, a request a session, without its Sensitive email or its context")
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
        let sut = DestinationConformance(limit: GoogleAnalyticsBatchEncoder.batchLimit) { setup in
            try HTTPDestination.googleAnalytics(
                measurementID: "G-TEST000000",
                apiSecret: "testapisecret",
                region: .global,
                plan: setup.plan,
                transport: setup.transport,
                backoff: setup.backoff,
                now: { Date(timeIntervalSince1970: 1_795_442_700) }
            )
        }

        try await sut.expectRequests(of: [first, second], plan: plan, matchFixture: "hand-worked-batch", subdirectory: "Fixtures", in: .module)
    }

    @Test("The destination posts JSON to the /mp/collect endpoint of the region, with the measurement ID and API secret in its query", arguments: [
        (GoogleAnalyticsRegion.global, "https://www.google-analytics.com/mp/collect?measurement_id=G-TEST000000&api_secret=testapisecret"),
        (.eu, "https://region1.google-analytics.com/mp/collect?measurement_id=G-TEST000000&api_secret=testapisecret"),
    ])
    func endpoint(region: GoogleAnalyticsRegion, expected: String) async throws {
        let plan = try TrackingPlan(schemas: [CheckoutStarted.schema])
        let record = EventRecord(event: CheckoutStarted(cartSize: 1, coupon: nil), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let transport = ScriptedTransport([.status(.noContent)])
        let sut = try HTTPDestination.googleAnalytics(measurementID: "G-TEST000000", apiSecret: "testapisecret", region: region, plan: plan, transport: transport, now: { Date(timeIntervalSince1970: 1_795_442_607) })
        let expectedMethod = HTTPRequest.Method.post
        let expectedContentType = "application/json"

        await sut.receive([record])

        let actual = try #require(transport.requests.first).request
        #expect(actual.url?.absoluteString == expected)
        #expect(actual.method == expectedMethod)
        #expect(actual.headerFields[.contentType] == expectedContentType)
    }

    @Test("The measurement ID and API secret are sent without the whitespace and newlines around them")
    func valuesTrimmed() async throws {
        let plan = try TrackingPlan(schemas: [CheckoutStarted.schema])
        let record = EventRecord(event: CheckoutStarted(cartSize: 1, coupon: nil), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let transport = ScriptedTransport([.status(.noContent)])
        let sut = try HTTPDestination.googleAnalytics(measurementID: " G-TEST000000\n", apiSecret: "\ttestapisecret \n", region: .global, plan: plan, transport: transport, now: { Date(timeIntervalSince1970: 1_795_442_607) })
        let expected = "https://www.google-analytics.com/mp/collect?measurement_id=G-TEST000000&api_secret=testapisecret"

        await sut.receive([record])

        let actual = try #require(transport.requests.first).request.url?.absoluteString
        #expect(actual == expected)
    }

    @Test("Every character of the API secret but a letter, digit, -, ., _ and ~ is percent-encoded, so the secret can't end the query's value", arguments: [
        ("aZ09-._~", "aZ09-._~"), ("a&b=c", "a%26b%3Dc"), ("a+b", "a%2Bb"), ("a b", "a%20b"), ("a#b", "a%23b"), ("a/b?c", "a%2Fb%3Fc"), ("a%b", "a%25b"), ("é", "%C3%A9"),
    ])
    func secretPercentEncoded(secret: String, expected: String) async throws {
        let plan = try TrackingPlan(schemas: [CheckoutStarted.schema])
        let record = EventRecord(event: CheckoutStarted(cartSize: 1, coupon: nil), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let transport = ScriptedTransport([.status(.noContent)])
        let sut = try HTTPDestination.googleAnalytics(measurementID: "G-TEST000000", apiSecret: secret, region: .global, plan: plan, transport: transport, now: { Date(timeIntervalSince1970: 1_795_442_607) })
        let expectedURL = "https://www.google-analytics.com/mp/collect?measurement_id=G-TEST000000&api_secret=\(expected)"

        await sut.receive([record])

        let actual = try #require(transport.requests.first).request.url?.absoluteString
        #expect(actual == expectedURL)
    }
}
#endif
