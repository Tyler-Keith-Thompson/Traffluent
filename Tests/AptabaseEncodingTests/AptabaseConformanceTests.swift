import AptabaseEncoding
import DestinationTesting
import EventMacros
import Foundation
import HTTPDestinations
import HTTPTypes
import Instrumentation
import Sessions
import StandardContext
import Testing
import TrackingPlans

@Suite("HTTPDestination.aptabase: conformance", .timeLimit(.minutes(1)))
struct AptabaseConformanceTests {
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

    // No Aptabase destination sends a Sensitive value, so there is no opted-in destination to
    // check. The kit's records are stamped at setup.timestamp, which the encoder takes as the time
    // each batch is encoded, so none falls outside the 23 hours.
    @Test("Aptabase's destination keeps every rule of a vendor destination", arguments: ConformanceCheck.allCases)
    func conformance(check: ConformanceCheck) async throws {
        let sut = DestinationConformance(limit: AptabaseBatchEncoder.batchLimit) { setup in
            try HTTPDestination.aptabase(appKey: "A-EU-1234567890", isDebug: false, plan: setup.plan, transport: setup.transport, backoff: setup.backoff, now: { setup.timestamp })
        }

        try await sut.expect(check)
    }

    // The fixture is a request to POST /api/v0/events as Aptabase's server reads it
    // (github.com/aptabase/aptabase at 89d36185, read 2026-11-27: EventsController.Multiple takes
    // an array of EventBody, src/Features/Ingestion/EventBody.cs, with eventName, timestamp,
    // sessionId, systemProps and props) and as the wiki's "How to build your own SDK" shows one,
    // checked by hand against both. The first record has the standard context and a session; the
    // second has no session, so its sessionId is its own id, and no context, so its systemProps
    // are isDebug and sdkVersion alone. 1,795,442,607 seconds after 1970 is 2026-11-23T14:03:27Z,
    // and 1,796,652,207 is 14 days later.
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
        let sut = DestinationConformance(limit: AptabaseBatchEncoder.batchLimit) { setup in
            try HTTPDestination.aptabase(appKey: "A-EU-1234567890", isDebug: false, plan: setup.plan, transport: setup.transport, backoff: setup.backoff, now: { Date(timeIntervalSince1970: 1_795_442_700) })
        }

        try await sut.expectRequests(of: [first, second], plan: plan, matchFixture: "hand-worked-batch", subdirectory: "Fixtures", in: .module)
    }

    // Aptabase's Swift SDK (github.com/aptabase/aptabase-swift at a1ee53e9, Aptabase.swift and
    // EventDispatcher.swift, read 2026-11-27) sends EU keys to https://eu.aptabase.com, US keys to
    // https://us.aptabase.com, and SH keys to the app's host, each at "\(baseUrl)/api/v0/events".
    @Test("The destination posts JSON to the key's region, or to the self-hosted host's path, with the key as its App-Key header field and no other", arguments: [
        ("A-EU-1234567890", nil, "https://eu.aptabase.com/api/v0/events"),
        ("A-US-1234567890", nil, "https://us.aptabase.com/api/v0/events"),
        ("A-SH-1234567890", "https://aptabase.example.com", "https://aptabase.example.com/api/v0/events"),
        ("A-SH-1234567890", "https://aptabase.example.com/", "https://aptabase.example.com/api/v0/events"),
        ("A-SH-1234567890", "https://example.com/aptabase//", "https://example.com/aptabase/api/v0/events"),
        ("A-SH-1234567890", "https://example.com:8443/a%20b/", "https://example.com:8443/a%20b/api/v0/events"),
        ("A-SH-1234567890", "HTTPS://Example.com/api", "HTTPS://Example.com/api/api/v0/events"),
        ("A-DEV-1234567890", "https://localhost:3000", "https://localhost:3000/api/v0/events"),
    ] as [(String, String?, String)])
    func endpoint(appKey: String, host: String?, expected: String) async throws {
        let plan = try TrackingPlan(schemas: [CheckoutStarted.schema])
        let tracked = Date(timeIntervalSince1970: 1_795_442_607)
        let record = EventRecord(event: CheckoutStarted(cartSize: 1, coupon: nil), timestamp: tracked, sourceLocation: nil)
        let transport = ScriptedTransport([.status(.ok)])
        let url = try host.map { try #require(URL(string: $0)) }
        let sut = try HTTPDestination.aptabase(appKey: appKey, host: url, isDebug: false, plan: plan, transport: transport, now: { tracked })
        let appKeyField = try #require(HTTPField.Name("App-Key"))
        let expectedMethod = HTTPRequest.Method.post
        let expectedContentType = "application/json"
        let expectedFieldNames: Set<HTTPField.Name> = [.contentType, appKeyField]

        await sut.receive([record])

        let actual = try #require(transport.requests.first).request
        #expect(actual.url?.absoluteString == expected)
        #expect(actual.method == expectedMethod)
        #expect(actual.headerFields[.contentType] == expectedContentType)
        #expect(actual.headerFields[appKeyField] == appKey)
        #expect(Set(actual.headerFields.map(\.name)) == expectedFieldNames)
    }
}
