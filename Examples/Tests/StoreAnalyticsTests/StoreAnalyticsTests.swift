import Foundation
import Events
import HTTPDestinations
import HTTPTypes
import Sessions
import StandardContext
import StoreAnalytics
import StoreEvents
import SystemPackage
import Testing
import Trackers
import TrackingPlans

@Suite("StoreAnalytics", .timeLimit(.minutes(1)))
struct StoreAnalyticsTests {
    /// A transport that answers every request with `status` and yields its body to `bodies`: the
    /// collector's side of these tests, with nothing sent.
    struct RecordingTransport: HTTPTransport {
        let status: HTTPResponse.Status
        let bodies: AsyncStream<Data>.Continuation

        func send(_ request: HTTPRequest, body: Data) async throws(HTTPTransportError) -> HTTPResponse {
            bodies.yield(body)
            return HTTPResponse(status: status)
        }
    }

    @Test("The collector receives each record with its session and context, and without its sensitive values")
    func redactedDelivery() async throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("StoreAnalyticsTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let endpoint = try #require(URL(string: "http://127.0.0.1:8080/v1/batches"))
        let (bodies, received) = AsyncStream.makeStream(of: Data.self)
        let sut = StoreAnalytics(
            collector: endpoint,
            consent: Consent([.analytics: .granted, .functional: .granted]),
            directory: directory,
            enrichers: [.sessions(), .operatingSystem()],
            transport: RecordingTransport(status: .noContent, bodies: received)
        )
        let expectedNames = ["SessionStarted", "signed_up"]
        let expectedProperties = ["plan", "referrer"]
        let expectedContext = ["operatingSystem", "session"]

        sut.tracker.track(SignedUp(plan: "plus", email: Sensitive("shopper@example.com"), referrer: nil))
        await sut.tracker.finish()
        try await sut.deliver()
        received.finish()

        var batches: [Data] = []
        for await body in bodies {
            batches.append(body)
        }
        let body = try #require(batches.first)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let records = try #require(json["records"] as? [[String: Any]])
        let signedUp = try #require(records.last)
        let properties = try #require(signedUp["properties"] as? [String: Any])
        let context = try #require(signedUp["context"] as? [String: Any])
        #expect(batches.count == 1)
        #expect(records.compactMap { $0["name"] as? String } == expectedNames)
        #expect(properties.keys.sorted() == expectedProperties)
        #expect(context.keys.sorted() == expectedContext)
        #expect(!String(decoding: body, as: UTF8.self).contains("shopper@example.com"))
    }

    @Test("With a tracking plan that throws, deliver() throws its error and nothing is sent")
    func invalidPlan() async throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("StoreAnalyticsTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let endpoint = try #require(URL(string: "http://127.0.0.1:8080/v1/batches"))
        let (bodies, received) = AsyncStream.makeStream(of: Data.self)
        let sut = StoreAnalytics(
            collector: endpoint,
            consent: Consent([.analytics: .granted, .functional: .granted]),
            directory: directory,
            transport: RecordingTransport(status: .noContent, bodies: received),
            trackingPlan: { () throws(TrackingPlanError) in
                try TrackingPlan(schemas: [EventSchema(name: "", version: 1, consentCategory: .analytics, properties: [])])
            }
        )

        sut.tracker.track(SignedUp(plan: "plus", email: Sensitive("shopper@example.com"), referrer: nil))
        await sut.tracker.finish()

        await #expect(throws: TrackingPlanError.emptyEventName) {
            try await sut.deliver()
        }
        received.finish()
        var batches: [Data] = []
        for await body in bodies {
            batches.append(body)
        }
        #expect(batches.isEmpty)
    }

    @Test("An event that breaks a constraint is reported as rejected and never sent")
    func rejected() async throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("StoreAnalyticsTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let endpoint = try #require(URL(string: "http://127.0.0.1:8080/v1/batches"))
        let (bodies, received) = AsyncStream.makeStream(of: Data.self)
        let sut = StoreAnalytics(
            collector: endpoint,
            consent: Consent([.analytics: .granted]),
            directory: directory,
            enrichers: [],
            transport: RecordingTransport(status: .noContent, bodies: received)
        )
        let expectedEventName = "product_added_to_cart"
        let expectedBodies = 0

        sut.tracker.track(ProductAddedToCart(productID: "canvas-tote", quantity: 0))
        await sut.tracker.finish()
        try await sut.deliver()
        received.finish()

        var actualEventName: String?
        for await drop in sut.drops {
            if case .rejected(let report) = drop {
                actualEventName = report.eventName
                break
            }
        }
        var actualBodies = 0
        for await _ in bodies {
            actualBodies += 1
        }
        #expect(actualEventName == expectedEventName)
        #expect(actualBodies == expectedBodies)
    }

    @Test("Events held while their category is undecided are reported as dropped once it is denied")
    func denied() async throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("StoreAnalyticsTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let endpoint = try #require(URL(string: "http://127.0.0.1:8080/v1/batches"))
        let (_, received) = AsyncStream.makeStream(of: Data.self)
        let consent = Consent()
        let sut = StoreAnalytics(
            collector: endpoint,
            consent: consent,
            directory: directory,
            enrichers: [],
            transport: RecordingTransport(status: .noContent, bodies: received)
        )
        let expectedCategory = ConsentCategory.advertising
        let expectedRecordCount = 2

        sut.tracker.track(PromotionTapped(campaign: "spring-sale"))
        sut.tracker.track(PromotionTapped(campaign: "spring-sale"))
        consent.deny(.advertising)
        await sut.tracker.flush()

        var actual: (category: ConsentCategory, recordCount: Int)?
        for await drop in sut.drops {
            if case .notConsented(.denied(let category, let recordCount, _)) = drop {
                actual = (category, recordCount)
                break
            }
        }
        #expect(actual?.category == expectedCategory)
        #expect(actual?.recordCount == expectedRecordCount)
        await sut.tracker.finish()
    }

    @Test("A batch the collector refuses is reported with its status and records")
    func refused() async throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("StoreAnalyticsTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let endpoint = try #require(URL(string: "http://127.0.0.1:8080/v1/batches"))
        let (_, received) = AsyncStream.makeStream(of: Data.self)
        let sut = StoreAnalytics(
            collector: endpoint,
            consent: Consent([.analytics: .granted]),
            directory: directory,
            enrichers: [],
            transport: RecordingTransport(status: .badRequest, bodies: received)
        )
        let expectedStatus = HTTPResponse.Status.badRequest
        let expectedRecordCount = 1

        sut.tracker.track(CheckoutStarted(cartSize: 2, coupon: nil))
        await sut.tracker.finish()
        try await sut.deliver()

        var actual: (status: HTTPResponse.Status, recordCount: Int)?
        for await drop in sut.drops {
            if case .notSent(.rejected(let status, let recordIDs)) = drop {
                actual = (status, recordIDs.count)
                break
            }
        }
        #expect(actual?.status == expectedStatus)
        #expect(actual?.recordCount == expectedRecordCount)
    }

    @Test("A record tracked but not delivered before the app ended is delivered on the next launch")
    func nextLaunch() async throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("StoreAnalyticsTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let endpoint = try #require(URL(string: "http://127.0.0.1:8080/v1/batches"))
        let (bodies, received) = AsyncStream.makeStream(of: Data.self)
        do {
            let firstLaunch = StoreAnalytics(
                collector: endpoint,
                consent: Consent([.analytics: .granted]),
                directory: directory,
                enrichers: [],
                transport: RecordingTransport(status: .noContent, bodies: received)
            )
            firstLaunch.tracker.track(CheckoutStarted(cartSize: 2, coupon: nil))
            await firstLaunch.tracker.finish()
        }
        let sut = StoreAnalytics(
            collector: endpoint,
            consent: Consent([.analytics: .granted]),
            directory: directory,
            enrichers: [],
            transport: RecordingTransport(status: .noContent, bodies: received)
        )
        let expected = ["checkout_started"]

        await sut.tracker.finish()
        try await sut.deliver()
        received.finish()

        var actual: [String] = []
        for await body in bodies {
            let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
            let records = try #require(json["records"] as? [[String: Any]])
            actual += records.compactMap { $0["name"] as? String }
        }
        #expect(actual == expected)
    }

    @Test("The store keeps every event the tracking plan lists, and no other")
    func storedEventsMatchThePlan() throws {
        let expected = try TrackingPlan.store.schemas.map(\.name).sorted()

        let actual = StoreAnalytics.storedEvents.map { $0.name }.sorted()

        #expect(actual == expected)
    }
}
