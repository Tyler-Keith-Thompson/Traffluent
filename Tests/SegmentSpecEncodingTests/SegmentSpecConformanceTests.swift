import DestinationTesting
import EventMacros
import Foundation
import HTTPDestinations
import HTTPTypes
import Instrumentation
import SegmentSpecEncoding
import Sessions
import StandardContext
import Testing
import TrackingPlans

// Private: its events share their names with other events of this test target, and @Event
// leaves a private type's events out of the link check of names (DefiningEvents, Limits).
@Suite("HTTPDestination.segment, .rudderStack and .customerIO: conformance", .timeLimit(.minutes(1)))
private struct SegmentSpecConformanceTests {
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

    /// Each factory, in each of its regions, as an adopter calls it.
    enum Endpoint: CaseIterable, CustomTestStringConvertible {
        case segmentUS, segmentEU, rudderStack, customerIOUS, customerIOEU, customerIOLegacy

        var testDescription: String {
            "\(self)"
        }

        /// The fixture of the hand-worked batch: RudderStack's calls carry `request_ip` too.
        var fixture: String {
            self == .rudderStack ? "hand-worked-batch-rudderstack" : "hand-worked-batch"
        }

        func destination(_ setup: DestinationSetup) throws -> HTTPDestination<ScriptedTransport, SegmentSpecBatchEncoder> {
            switch self {
            case .segmentUS:
                try HTTPDestination.segment(writeKey: "testwritekey", region: .us, plan: setup.plan, transport: setup.transport, backoff: setup.backoff)
            case .segmentEU:
                try HTTPDestination.segment(writeKey: "testwritekey", region: .eu, plan: setup.plan, transport: setup.transport, backoff: setup.backoff)
            case .rudderStack:
                try HTTPDestination.rudderStack(writeKey: "testwritekey", dataPlane: URL(string: "https://exampledataplane.rudderstack.com")!, plan: setup.plan, transport: setup.transport, backoff: setup.backoff)
            case .customerIOUS:
                try HTTPDestination.customerIO(apiKey: "pk_us_testkey", region: .us, plan: setup.plan, transport: setup.transport, backoff: setup.backoff)
            case .customerIOEU:
                try HTTPDestination.customerIO(apiKey: "pk_eu_testkey", region: .eu, plan: setup.plan, transport: setup.transport, backoff: setup.backoff)
            case .customerIOLegacy:
                try HTTPDestination.customerIO(apiKey: "testwritekey", region: .us, plan: setup.plan, transport: setup.transport, backoff: setup.backoff)
            }
        }
    }

    // No Segment-spec destination sends a Sensitive value, so there is no opted-in destination to
    // check. The Authorization field the factories add holds no trace context, so
    // traceContextWithheld still holds with it.
    @Test("Each Segment-spec destination keeps every rule of a vendor destination, in every region", arguments: ConformanceCheck.allCases, Endpoint.allCases)
    func conformance(check: ConformanceCheck, endpoint: Endpoint) async throws {
        let sut = DestinationConformance(limit: SegmentSpecBatchEncoder.batchLimit) { setup in
            try endpoint.destination(setup)
        }

        try await sut.expect(check)
    }

    // The fixture is the batch call of Segment's HTTP Tracking API
    // (https://segment.com/docs/connections/sources/catalog/libraries/server/http-api/, "Batch")
    // with the track call and context fields of its Spec
    // (https://segment.com/docs/connections/spec/common/), checked by hand against them: the first
    // record has the standard context and a session, the second a session alone. Every factory
    // posts the same body, but RudderStack's, whose calls also carry `request_ip` "0.0.0.0"
    // (https://www.rudderstack.com/docs/event-spec/standard-events/common-fields/).
    @Test("A hand-worked batch is posted as the recorded fixture, byte for byte, without its Sensitive email, by every factory", arguments: Endpoint.allCases)
    func handWorkedFixture(endpoint: Endpoint) async throws {
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
        let sut = DestinationConformance(limit: SegmentSpecBatchEncoder.batchLimit) { setup in
            try endpoint.destination(setup)
        }

        try await sut.expectRequests(of: [first, second], plan: plan, matchFixture: endpoint.fixture, subdirectory: "Fixtures", in: .module)
    }

    @Test("Segment's destination posts JSON to its region's /v1/batch, with the write key as Basic auth's user name and an empty password", arguments: [
        (SegmentRegion.us, "https://api.segment.io/v1/batch"),
        (.eu, "https://events.eu1.segmentapis.com/v1/batch"),
    ])
    func segmentEndpoint(region: SegmentRegion, expected: String) async throws {
        let plan = try TrackingPlan(schemas: [CheckoutStarted.schema])
        let record = EventRecord(event: CheckoutStarted(cartSize: 1, coupon: nil), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let transport = ScriptedTransport([.status(.ok)])
        let sut = try HTTPDestination.segment(writeKey: " abc123\n", region: region, plan: plan, transport: transport)
        // Segment's own example: the write key abc123, a colon, then base64.
        let expectedAuthorization = "Basic YWJjMTIzOg=="
        let expectedMethod = HTTPRequest.Method.post
        let expectedContentType = "application/json"

        await sut.receive([record])

        let actual = try #require(transport.requests.first).request
        #expect(actual.url?.absoluteString == expected)
        #expect(actual.method == expectedMethod)
        #expect(actual.headerFields[.contentType] == expectedContentType)
        #expect(actual.headerFields[.authorization] == expectedAuthorization)
        #expect(actual.headerFields[HTTPField.Name("X-Strict-Mode")!] == nil)
    }

    @Test("RudderStack's destination posts JSON to the data plane's /v1/batch, after its path, with the write key as Basic auth's user name", arguments: [
        ("https://exampledataplane.rudderstack.com", "https://exampledataplane.rudderstack.com/v1/batch"),
        ("https://exampledataplane.rudderstack.com/", "https://exampledataplane.rudderstack.com/v1/batch"),
        ("https://rudder.example.com/ingest", "https://rudder.example.com/ingest/v1/batch"),
        ("https://rudder.example.com:8443/a%2Fb//", "https://rudder.example.com:8443/a%2Fb/v1/batch"),
        ("HTTPS://rudder.example.com", "HTTPS://rudder.example.com/v1/batch"),
    ])
    func rudderStackEndpoint(dataPlane: String, expected: String) async throws {
        let plan = try TrackingPlan(schemas: [CheckoutStarted.schema])
        let record = EventRecord(event: CheckoutStarted(cartSize: 1, coupon: nil), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let transport = ScriptedTransport([.status(.ok)])
        let sut = try HTTPDestination.rudderStack(writeKey: "\tabc123 ", dataPlane: try #require(URL(string: dataPlane)), plan: plan, transport: transport)
        let expectedAuthorization = "Basic YWJjMTIzOg=="
        let expectedContentType = "application/json"

        await sut.receive([record])

        let actual = try #require(transport.requests.first).request
        #expect(actual.url?.absoluteString == expected)
        #expect(actual.headerFields[.contentType] == expectedContentType)
        #expect(actual.headerFields[.authorization] == expectedAuthorization)
    }

    @Test("Customer.io's destination posts JSON to its region's /v1/batch, with the key as a bearer token, in strict mode", arguments: [
        (CustomerIORegion.us, "pk_us_abc123", "https://cdp.customer.io/v1/batch"),
        (.eu, "pk_eu_abc123", "https://cdp-eu.customer.io/v1/batch"),
        (.eu, "abc123", "https://cdp-eu.customer.io/v1/batch"),
    ])
    func customerIOEndpoint(region: CustomerIORegion, apiKey: String, expected: String) async throws {
        let plan = try TrackingPlan(schemas: [CheckoutStarted.schema])
        let record = EventRecord(event: CheckoutStarted(cartSize: 1, coupon: nil), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let transport = ScriptedTransport([.status(.ok)])
        let sut = try HTTPDestination.customerIO(apiKey: " \(apiKey)\n", region: region, plan: plan, transport: transport)
        let expectedAuthorization = "Bearer \(apiKey)"
        let expectedStrictMode = "1"
        let expectedContentType = "application/json"

        await sut.receive([record])

        let actual = try #require(transport.requests.first).request
        #expect(actual.url?.absoluteString == expected)
        #expect(actual.headerFields[.contentType] == expectedContentType)
        #expect(actual.headerFields[.authorization] == expectedAuthorization)
        #expect(actual.headerFields[HTTPField.Name("X-Strict-Mode")!] == expectedStrictMode)
    }

    @Test("RudderStack's calls carry a top-level request_ip of 0.0.0.0, and Segment's and Customer.io's carry none", arguments: Endpoint.allCases)
    func requestIP(endpoint: Endpoint) async throws {
        let plan = try TrackingPlan(schemas: [CheckoutStarted.schema])
        let batch = [
            EventRecord(event: CheckoutStarted(cartSize: 1, coupon: nil), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil),
            EventRecord(event: CheckoutStarted(cartSize: 2, coupon: nil), timestamp: Date(timeIntervalSince1970: 1_795_442_608), sourceLocation: nil),
        ]
        let transport = ScriptedTransport([.status(.ok)])
        let sut = try endpoint.destination(DestinationSetup(plan: plan, transport: transport, backoff: ExponentialBackoff()))
        let expected: [String?] = endpoint == .rudderStack ? ["0.0.0.0", "0.0.0.0"] : [nil, nil]

        await sut.receive(batch)

        let body = try #require(transport.requests.first).body
        let calls = try #require((try JSONSerialization.jsonObject(with: body) as? [String: Any])?["batch"] as? [[String: Any]])
        let actual = calls.map { $0["request_ip"] as? String }
        #expect(actual == expected)
    }

    @Test("The write key is sent only in the Authorization field, never in the body")
    func keyNotInBody() async throws {
        let plan = try TrackingPlan(schemas: [CheckoutStarted.schema])
        let record = EventRecord(id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!, event: CheckoutStarted(cartSize: 1, coupon: nil), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let transport = ScriptedTransport([.status(.ok)])
        let sut = try HTTPDestination.segment(writeKey: "qwertyuiopwritekey", region: .us, plan: plan, transport: transport)

        await sut.receive([record])

        let body = String(decoding: try #require(transport.requests.first).body, as: UTF8.self)
        #expect(!body.contains("qwertyuiopwritekey"))
        #expect(!body.contains("writeKey"))
    }
}
