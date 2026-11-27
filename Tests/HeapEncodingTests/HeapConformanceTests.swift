import DestinationTesting
import EventMacros
import Foundation
import HeapEncoding
import HTTPDestinations
import HTTPTypes
import Instrumentation
import Sessions
import StandardContext
import Testing
import TrackingPlans

@Suite("HTTPDestination.heap: conformance", .timeLimit(.minutes(1)))
struct HeapConformanceTests {
    @Event(name: "signed_up")
    struct SignedUp {
        var plan: String
        var email: Sensitive<String>
        var referrer: String?
        var seats: Int
        var discount: Double
        var newsletter: Bool
        var trialEndsAt: Date
        var tags: [String]
    }

    @Event(name: "Checkout.started", version: 2)
    struct CheckoutStarted {
        var cartSize: Int
        var coupon: String?
    }

    // No Heap destination sends a Sensitive value, so there is no opted-in destination to check.
    @Test("Heap's destination keeps every rule of a vendor destination", arguments: ConformanceCheck.allCases)
    func conformance(check: ConformanceCheck) async throws {
        let sut = DestinationConformance(limit: HeapBatchEncoder.batchLimit) { setup in
            try HTTPDestination.heap(appID: "12343283", region: .us, plan: setup.plan, transport: setup.transport, backoff: setup.backoff)
        }

        try await sut.expect(check)
    }

    // The fixture is a bulk track request as https://developers.heap.io/reference/bulk-track and
    // https://developers.heap.io/reference/track-1 show it (read 2026-11-27): app_id beside an
    // `events` array, each event's event, identity, idempotency_key, properties and an ISO 8601
    // timestamp, checked by hand against both. The first record has the standard context, which
    // isn't sent, and a session; the second has no session, so its identity is its own id.
    // 1,795,442,607 seconds after 1970 is 2026-11-23T14:03:27Z, and 1,796,652,207 is 14 days later.
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
            newsletter: true,
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
        let second = EventRecord(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!,
            event: CheckoutStarted(cartSize: 2, coupon: nil),
            timestamp: Date(timeIntervalSince1970: 1_795_442_608.25),
            sourceLocation: nil,
            isRedelivered: true
        )
        let sut = DestinationConformance(limit: HeapBatchEncoder.batchLimit) { setup in
            try HTTPDestination.heap(appID: "12343283", region: .us, plan: setup.plan, transport: setup.transport, backoff: setup.backoff)
        }

        try await sut.expectRequests(of: [first, second], plan: plan, matchFixture: "hand-worked-batch", subdirectory: "Fixtures", in: .module)
    }

    // https://developers.heap.io/reference/track-1: "If your Heap data is in an EU datacenter,
    // the correct endpoint is: https://c.eu.heap-api.com/api/track (NOT heapanalytics.com)".
    @Test("The destination posts JSON to the region's track endpoint, with no other header field", arguments: [
        (HeapRegion.us, "https://heapanalytics.com/api/track"),
        (HeapRegion.eu, "https://c.eu.heap-api.com/api/track"),
    ])
    func endpoint(region: HeapRegion, expected: String) async throws {
        let plan = try TrackingPlan(schemas: [CheckoutStarted.schema])
        let record = EventRecord(event: CheckoutStarted(cartSize: 1, coupon: nil), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let transport = ScriptedTransport([.status(.ok)])
        let sut = try HTTPDestination.heap(appID: "12343283", region: region, plan: plan, transport: transport)
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
}
