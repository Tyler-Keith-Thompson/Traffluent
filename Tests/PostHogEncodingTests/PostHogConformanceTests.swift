import DestinationTesting
import EventMacros
import Foundation
import HTTPDestinations
import Instrumentation
import PostHogEncoding
import Sessions
import StandardContext
import Testing
import TrackingPlans

// Private: its events share their names with other events of this test target, and @Event
// leaves a private type's events out of the link check of names (DefiningEvents, Limits).
@Suite("HTTPDestination.postHog: conformance", .timeLimit(.minutes(1)))
private struct PostHogConformanceTests {
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

    // PostHog never sends a Sensitive value, so there is no opted-in destination to check.
    @Test("The PostHog destination keeps every rule of a vendor destination", arguments: ConformanceCheck.allCases)
    func conformance(check: ConformanceCheck) async throws {
        let host = try #require(URL(string: "https://posthog.example.com"))
        let sut = DestinationConformance(limit: PostHogBatchEncoder.batchLimit) { setup in
            try HTTPDestination.postHog(projectToken: "phc_test", host: host, plan: setup.plan, transport: setup.transport, backoff: setup.backoff)
        }

        try await sut.expect(check)
    }

    @Test("A hand-worked batch is posted as the recorded fixture, byte for byte, without its Sensitive email")
    func handWorkedFixture() async throws {
        let host = try #require(URL(string: "https://posthog.example.com"))
        let plan = try TrackingPlan(schemas: [SignedUp.schema, CheckoutStarted.schema])
        var context = ServiceContext.topLevel
        context[ApplicationKey.self] = ApplicationKey.Value(bundleIdentifier: "com.example.shop", version: "2.4.1", build: "418")
        context[DeviceKey.self] = DeviceKey.Value(model: "iPhone17,1", formFactor: .phone)
        context[LocaleKey.self] = Locale(identifier: "en_US")
        context[NetworkKey.self] = .wifi
        context[OperatingSystemKey.self] = OperatingSystemKey.Value(name: "iOS", version: "26.1.0")
        context[SessionKey.self] = UUID(uuidString: "00000000-0000-4000-8000-00000000000A")!
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
        let sut = DestinationConformance(limit: PostHogBatchEncoder.batchLimit) { setup in
            try HTTPDestination.postHog(projectToken: "phc_test", host: host, plan: setup.plan, transport: setup.transport, backoff: setup.backoff)
        }

        try await sut.expectRequests(of: [first, second], plan: plan, matchFixture: "hand-worked-batch", subdirectory: "Fixtures", in: .module)
    }

    @Test("The token is sent without the whitespace and newlines around it")
    func tokenTrimmed() async throws {
        let host = try #require(URL(string: "https://posthog.example.com"))
        let plan = try TrackingPlan(schemas: [CheckoutStarted.schema])
        let record = EventRecord(event: CheckoutStarted(cartSize: 1, coupon: nil), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)
        let transport = ScriptedTransport([.status(.ok)])
        let sut = try HTTPDestination.postHog(projectToken: " phc_test\n", host: host, plan: plan, transport: transport)
        let expected = #"{"api_key":"phc_test","batch":["#

        await sut.receive([record])

        let actual = String(decoding: try #require(transport.requests.first).body, as: UTF8.self)
        #expect(actual.hasPrefix(expected))
    }

    @Test("The destination posts to the host's /batch/, keeping a path the host is served under, percent escapes and all")
    func endpoint() async throws {
        let hosts = [
            "https://posthog.example.com", "https://posthog.example.com/", "https://example.com/posthog", "https://example.com/posthog//",
            "https://[::1]", "https://[2001:db8::1]:8443/posthog", "https://example.com/a%2Fb", "https://example.com/caf%C3%A9",
        ]
        let expected: [String?] = [
            "https://posthog.example.com/batch/", "https://posthog.example.com/batch/", "https://example.com/posthog/batch/", "https://example.com/posthog/batch/",
            "https://[::1]/batch/", "https://[2001:db8::1]:8443/posthog/batch/", "https://example.com/a%2Fb/batch/", "https://example.com/caf%C3%A9/batch/",
        ]
        let plan = try TrackingPlan(schemas: [CheckoutStarted.schema])
        let record = EventRecord(event: CheckoutStarted(cartSize: 1, coupon: nil), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)
        var actual: [String?] = []

        for host in hosts {
            let transport = ScriptedTransport([.status(.ok)])
            let sut = try HTTPDestination.postHog(projectToken: "phc_test", host: try #require(URL(string: host)), plan: plan, transport: transport)
            await sut.receive([record])
            actual.append(transport.requests.first?.request.url?.absoluteString)
        }

        #expect(actual == expected)
    }
}
