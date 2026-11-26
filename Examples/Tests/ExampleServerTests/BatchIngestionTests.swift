import CollectorEncoding
import Destinations
import Events
import ExampleServer
import Foundation
import HTTPDestinations
import Hummingbird
import HummingbirdTesting
import InMemoryTracing
import Instrumentation
import StoreAnalytics
import StoreEvents
import StoreModel
import SystemPackage
import Testing
import Trackers
import Tracing
import TrackingPlans

@Suite("The server example's collector route", .timeLimit(.minutes(1)))
struct BatchIngestionTests {
    @Test("A batch an app's HTTPDestination sends is handled in a server span that shares the app event's trace ID")
    func sharesTraceID() async throws {
        let appTracer = InMemoryTracer()
        // IDs of the server's own, so a span it starts outside the app's trace can't match by chance.
        let serverTracer = InMemoryTracer(idGenerator: .init(nextTraceID: { "server-trace" }, nextSpanID: { "server-span" }))
        let sut = Application(router: buildRouter(tracer: serverTracer))
        let tracker = Tracker()
        let checkout = appTracer.startSpan("checkout")
        let expectedTraceID = checkout.traceID
        let expectedParentSpanID = checkout.spanID
        let expectedEvents = ["checkout_started"]

        ServiceContext.withValue(checkout.context) {
            tracker.track(CheckoutStarted(cartSize: 1, coupon: nil))
        }
        checkout.end()
        await tracker.finish()
        try await sut.test(.live) { client in
            let port = try #require(client.port)
            let endpoint = try #require(URL(string: "http://localhost:\(port)/v1/batches"))
            let app = HTTPDestination(endpoint: endpoint, instrument: appTracer, encoder: CollectorBatchEncoder(plan: try .store))
            try await tracker.records.batch().deliver(to: app).execute()
        }

        let actual = try #require(serverTracer.finishedSpans.first { $0.operationName == "POST /v1/batches" })
        #expect(actual.traceID == expectedTraceID)
        #expect(actual.spanContext.parentSpanID == expectedParentSpanID)
        #expect(actual.kind == .server)
        #expect(actual.events.map(\.name) == expectedEvents)
    }

    @Test("Each record's span event carries the record's identifier, as the app's tracker gave it")
    func recordIdentifiers() async throws {
        let serverTracer = InMemoryTracer()
        let sut = Application(router: buildRouter(tracer: serverTracer))
        let tracker = Tracker()
        let memory = InMemoryDestination()

        tracker.track(CheckoutStarted(cartSize: 1, coupon: nil))
        tracker.track(CheckoutStarted(cartSize: 1, coupon: nil))
        await tracker.finish()
        try await sut.test(.live) { client in
            let port = try #require(client.port)
            let endpoint = try #require(URL(string: "http://localhost:\(port)/v1/batches"))
            let app = HTTPDestination(endpoint: endpoint, instrument: NoOpInstrument(), encoder: CollectorBatchEncoder(plan: try .store))
            try await tracker.records.batch().deliver(to: app, memory).execute()
        }

        let expected: [SpanAttribute?] = memory.records.map { .string($0.id.uuidString) }
        let span = try #require(serverTracer.finishedSpans.first { $0.operationName == "POST /v1/batches" })
        let actual = span.events.map { $0.attributes.get("record.id") }
        #expect(actual == expected)
        #expect(Set(memory.records.map(\.id)).count == 2)
    }

    @Test("A batch sent without trace context is handled in a server span of a trace of the server's own")
    func noTraceContext() async throws {
        let appTracer = InMemoryTracer()
        let serverTracer = InMemoryTracer(idGenerator: .init(nextTraceID: { "server-trace" }, nextSpanID: { "server-span" }))
        let sut = Application(router: buildRouter(tracer: serverTracer))
        let tracker = Tracker()
        let checkout = appTracer.startSpan("checkout")
        let expectedTraceID = "server-trace"

        ServiceContext.withValue(checkout.context) {
            tracker.track(CheckoutStarted(cartSize: 1, coupon: nil))
        }
        checkout.end()
        await tracker.finish()
        try await sut.test(.live) { client in
            let port = try #require(client.port)
            let endpoint = try #require(URL(string: "http://localhost:\(port)/v1/batches"))
            let app = HTTPDestination(endpoint: endpoint, instrument: NoOpInstrument(), encoder: CollectorBatchEncoder(plan: try .store))
            try await tracker.records.batch().deliver(to: app).execute()
        }

        let actual = try #require(serverTracer.finishedSpans.first { $0.operationName == "POST /v1/batches" })
        #expect(actual.traceID == expectedTraceID)
        #expect(actual.spanContext.parentSpanID == nil)
    }

    @Test("The store app's analytics deliver a shopping trip to the server, the account's event included")
    func storeAnalytics() async throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("BatchIngestionTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let serverTracer = InMemoryTracer()
        let sut = Application(router: buildRouter(tracer: serverTracer))
        let tote = Product(id: "canvas-tote", name: "Canvas Tote", priceInCents: 2_400)
        let expected = ["product_added_to_cart", "checkout_started", "order_completed", "signed_up"]

        try await sut.test(.live) { client in
            let port = try #require(client.port)
            let endpoint = try #require(URL(string: "http://localhost:\(port)/v1/batches"))
            let analytics = StoreAnalytics(
                collector: endpoint,
                consent: Consent([.analytics: .granted, .functional: .granted, .advertising: .granted]),
                directory: directory,
                enrichers: [],
                // A send that fails for now is retried at once, so a hiccup on localhost can't
                // hold the test up for real seconds.
                backoff: try ExponentialBackoff(initialDelay: .milliseconds(1), maximumDelay: .milliseconds(1))
            )
            var cart = Cart()
            try withTracker(analytics.tracker) {
                try cart.add(tote)
                cart.startCheckout()
                _ = cart.placeOrder(expressShipping: false)
                _ = Account.signUp(email: "shopper@example.com", plan: .basic)
            }
            await analytics.tracker.finish()
            try await analytics.deliver()
        }

        let actual = serverTracer.finishedSpans.filter { $0.operationName == "POST /v1/batches" }.flatMap { $0.events.map(\.name) }
        #expect(actual == expected)
    }

    @Test("The collector route answers 204 No Content to a collector batch")
    func noContent() async throws {
        let sut = Application(router: buildRouter())
        let body = #"{"records":[{"id":"E621E1F8-C36C-495A-93FC-0C247A3E6E5F","name":"checkout_started","isRedelivered":false}]}"#
        let expected = HTTPResponse.Status.noContent

        let actual = try await sut.test(.router) { client in
            try await client.execute(uri: "/v1/batches", method: .post, body: ByteBuffer(string: body)) { response in
                response.status
            }
        }

        #expect(actual == expected)
    }

    @Test(
        "A body that isn't a collector batch answers 400 Bad Request",
        arguments: [
            "checkout_started",
            #"{"records":[{"id":"not-a-uuid","name":"checkout_started","isRedelivered":false}]}"#,
            #"{"records":[{"id":"E621E1F8-C36C-495A-93FC-0C247A3E6E5F","isRedelivered":false}]}"#,
        ]
    )
    func malformedBody(body: String) async throws {
        let sut = Application(router: buildRouter())
        let expected = HTTPResponse.Status.badRequest

        let actual = try await sut.test(.router) { client in
            try await client.execute(uri: "/v1/batches", method: .post, body: ByteBuffer(string: body)) { response in
                response.status
            }
        }

        #expect(actual == expected)
    }
}
