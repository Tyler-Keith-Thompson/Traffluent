import DestinationTesting
import EventMacros
import Foundation
import HTTPDestinations
import HTTPTypes
import Instrumentation
import MixpanelEncoding
import Sessions
import StandardContext
import Testing
import TrackingPlans

@Suite("HTTPDestination.mixpanel: conformance", .timeLimit(.minutes(1)))
struct MixpanelConformanceTests {
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

    // Mixpanel never sends a Sensitive value, so there is no opted-in destination to check.
    @Test("The Mixpanel destination keeps every rule of a vendor destination, in every region", arguments: ConformanceCheck.allCases, [MixpanelRegion.us, .eu, .india])
    func conformance(check: ConformanceCheck, region: MixpanelRegion) async throws {
        let sut = DestinationConformance(limit: MixpanelBatchEncoder.batchLimit) { setup in
            try HTTPDestination.mixpanel(projectToken: "0123456789abcdef0123456789abcdef", region: region, plan: setup.plan, transport: setup.transport, backoff: setup.backoff, now: { setup.timestamp })
        }

        try await sut.expect(check)
    }

    // The fixture is the request of Mixpanel's track reference
    // (https://developer.mixpanel.com/reference/track-event, "OpenAPI", and
    // https://developer.mixpanel.com/reference/import-events, "properties.time" and
    // "properties.$insert_id"), checked by hand against it: the first record has the standard
    // context and a session, the second a session alone.
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
        let sut = DestinationConformance(limit: MixpanelBatchEncoder.batchLimit) { setup in
            try HTTPDestination.mixpanel(projectToken: "0123456789abcdef0123456789abcdef", region: .us, plan: setup.plan, transport: setup.transport, backoff: setup.backoff, now: { Date(timeIntervalSince1970: 1_795_442_607) })
        }

        try await sut.expectRequests(of: [first, second], plan: plan, matchFixture: "hand-worked-batch", subdirectory: "Fixtures", in: .module)
    }

    @Test("The project token is sent without the whitespace and newlines around it")
    func projectTokenTrimmed() async throws {
        let plan = try TrackingPlan(schemas: [CheckoutStarted.schema])
        let record = EventRecord(event: CheckoutStarted(cartSize: 1, coupon: nil), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let transport = ScriptedTransport([.status(.ok)])
        let sut = try HTTPDestination.mixpanel(projectToken: " testprojecttoken\n", region: .us, plan: plan, transport: transport, now: { Date(timeIntervalSince1970: 1_795_442_607) })
        let expected = #","token":"testprojecttoken"}}]"#

        await sut.receive([record])

        let actual = String(decoding: try #require(transport.requests.first).body, as: UTF8.self)
        #expect(actual.hasSuffix(expected))
    }

    @Test("The destination posts JSON to the /track endpoint of the project's region, with ip=0 and verbose=1", arguments: [
        (MixpanelRegion.us, "https://api.mixpanel.com/track?ip=0&verbose=1"),
        (.eu, "https://api-eu.mixpanel.com/track?ip=0&verbose=1"),
        (.india, "https://api-in.mixpanel.com/track?ip=0&verbose=1"),
    ])
    func endpoint(region: MixpanelRegion, expected: String) async throws {
        let plan = try TrackingPlan(schemas: [CheckoutStarted.schema])
        let record = EventRecord(event: CheckoutStarted(cartSize: 1, coupon: nil), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let transport = ScriptedTransport([.status(.ok)])
        let sut = try HTTPDestination.mixpanel(projectToken: "testprojecttoken", region: region, plan: plan, transport: transport, now: { Date(timeIntervalSince1970: 1_795_442_607) })
        let expectedMethod = HTTPRequest.Method.post
        let expectedContentType = "application/json"

        await sut.receive([record])

        let actual = try #require(transport.requests.first).request
        #expect(actual.url?.absoluteString == expected)
        #expect(actual.method == expectedMethod)
        #expect(actual.headerFields[.contentType] == expectedContentType)
    }
}
