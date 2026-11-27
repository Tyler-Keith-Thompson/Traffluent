import DestinationTesting
import EventMacros
import Foundation
import HTTPDestinations
import HTTPTypes
import Instrumentation
import MatomoEncoding
import Sessions
import StandardContext
import Testing
import TrackingPlans

@Suite("HTTPDestination.matomo: conformance", .timeLimit(.minutes(1)))
struct MatomoConformanceTests {
    @Event(name: "signed_up")
    struct SignedUp {
        var plan: String
        var email: Sensitive<String>
        var referrer: String?
        var seats: Int
        var discount: Double
        var tags: [String]
        var note: String
    }

    @Event(name: "checkout_started", version: 2)
    struct CheckoutStarted {
        var cartSize: Int
        var coupon: String?
    }

    // Matomo never receives a Sensitive value, so there is no opted-in destination to check. Every
    // check's plan has a `label` property, the one the checks find a record by, so it is the
    // dimension. The kit's records are stamped at setup.timestamp, which the encoder takes as the
    // time each batch is encoded, so none falls outside the 23 hours.
    @Test("The Matomo destination keeps every rule of a vendor destination", arguments: ConformanceCheck.allCases)
    func conformance(check: ConformanceCheck) async throws {
        let url = try #require(URL(string: "https://analytics.example.com"))
        let sut = DestinationConformance(limit: MatomoBatchEncoder.batchLimit) { setup in
            try HTTPDestination.matomo(
                url: url,
                siteID: 1,
                dimensions: ["label": 1],
                category: "Traffluent",
                plan: setup.plan,
                transport: setup.transport,
                backoff: setup.backoff,
                now: { setup.timestamp }
            )
        }

        try await sut.expect(check)
    }

    // Checked by hand against Matomo's Tracking HTTP API reference
    // (https://developer.matomo.org/api-reference/tracking-api, "Bulk Tracking", read on
    // 2026-11-27) and the tracker's parsing in matomo-org/matomo 6.0.0
    // (plugins/BulkTracking/Tracker/Requests.php: parse_url, then parse_str of each request): the
    // first record has a version 7 session, a locale, an unmapped Sensitive email, a nil referrer
    // and values to escape; the second has no session, so its visitor is its own ID.
    @Test("A hand-worked batch is posted as the recorded fixture, byte for byte, without its Sensitive email or its unmapped coupon")
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
            tags: ["beta", "ios"],
            note: "Tom & Jerry's"
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
            event: CheckoutStarted(cartSize: 2, coupon: "SPRING"),
            timestamp: Date(timeIntervalSince1970: 1_795_442_608.25),
            sourceLocation: nil,
            isRedelivered: true
        )
        let url = try #require(URL(string: "https://analytics.example.com"))
        let sut = DestinationConformance(limit: MatomoBatchEncoder.batchLimit) { setup in
            try HTTPDestination.matomo(
                url: url,
                siteID: 3,
                dimensions: ["plan": 1, "seats": 2, "discount": 3, "tags": 4, "referrer": 5, "note": 7, "cartSize": 8],
                category: "Shop & Co",
                plan: setup.plan,
                transport: setup.transport,
                backoff: setup.backoff,
                now: { Date(timeIntervalSince1970: 1_795_442_700) }
            )
        }

        try await sut.expectRequests(of: [first, second], plan: plan, matchFixture: "hand-worked-batch", subdirectory: "Fixtures", in: .module)
    }

    @Test("The destination posts JSON to matomo.php under the installation's URL, its path and percent escapes kept, whatever slashes end it", arguments: [
        ("https://analytics.example.com", "https://analytics.example.com/matomo.php"),
        ("https://analytics.example.com/", "https://analytics.example.com/matomo.php"),
        ("https://example.com/matomo", "https://example.com/matomo/matomo.php"),
        ("https://example.com/matomo//", "https://example.com/matomo/matomo.php"),
        ("https://example.com/a%20b/", "https://example.com/a%20b/matomo.php"),
        ("https://example.com:8443/stats/", "https://example.com:8443/stats/matomo.php"),
        ("HTTPS://Example.com/php/", "HTTPS://Example.com/php/matomo.php"),
        ("https://example.com/matomo.php/stats", "https://example.com/matomo.php/stats/matomo.php"),
    ])
    func endpoint(url: String, expected: String) async throws {
        let plan = try TrackingPlan(schemas: [CheckoutStarted.schema])
        let record = EventRecord(event: CheckoutStarted(cartSize: 1, coupon: nil), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let transport = ScriptedTransport([.status(.ok)])
        let installation = try #require(URL(string: url))
        let sut = try HTTPDestination.matomo(url: installation, siteID: 1, dimensions: [:], category: "Shop", plan: plan, transport: transport, now: { Date(timeIntervalSince1970: 1_795_442_607) })
        let expectedMethod = HTTPRequest.Method.post
        let expectedContentType = "application/json"

        await sut.receive([record])

        let actual = try #require(transport.requests.first).request
        #expect(actual.url?.absoluteString == expected)
        #expect(actual.method == expectedMethod)
        #expect(actual.headerFields[.contentType] == expectedContentType)
    }

    @Test("No request holds a token_auth, in its URL, its header fields or its body")
    func noTokenAuth() async throws {
        let plan = try TrackingPlan(schemas: [CheckoutStarted.schema])
        let record = EventRecord(event: CheckoutStarted(cartSize: 1, coupon: nil), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let transport = ScriptedTransport([.status(.ok)])
        let url = try #require(URL(string: "https://analytics.example.com"))
        let sut = try HTTPDestination.matomo(url: url, siteID: 1, dimensions: [:], category: "Shop", plan: plan, transport: transport, now: { Date(timeIntervalSince1970: 1_795_442_607) })
        let expectedHeaderFields: HTTPFields = [.contentType: "application/json"]

        await sut.receive([record])

        let actual = try #require(transport.requests.first)
        #expect(actual.request.url?.query == nil)
        #expect(actual.request.headerFields == expectedHeaderFields)
        #expect(!String(decoding: actual.body, as: UTF8.self).contains("token"))
    }
}
