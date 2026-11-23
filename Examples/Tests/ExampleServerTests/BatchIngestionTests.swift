import Events
import ExampleEvents
import ExampleServer
import Foundation
import HTTPDestinations
import Hummingbird
import HummingbirdTesting
import InMemoryTracing
import Instrumentation
import Testing
import Trackers
import Tracing

@Suite("The server example's batches route", .timeLimit(.minutes(1)))
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
        let expectedEvents = ["ButtonTapped"]

        ServiceContext.withValue(checkout.context) {
            tracker.track(ButtonTapped(label: "Buy"))
        }
        checkout.end()
        await tracker.finish()
        try await sut.test(.live) { client in
            let port = try #require(client.port)
            let endpoint = try #require(URL(string: "http://localhost:\(port)/batches"))
            let app = HTTPDestination(endpoint: endpoint, instrument: appTracer, encoder: EventNamesEncoder())
            try await tracker.records.batch().deliver(to: app).execute()
        }

        let actual = try #require(serverTracer.finishedSpans.first { $0.operationName == "POST /batches" })
        #expect(actual.traceID == expectedTraceID)
        #expect(actual.spanContext.parentSpanID == expectedParentSpanID)
        #expect(actual.kind == .server)
        #expect(actual.events.map(\.name) == expectedEvents)
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
            tracker.track(ButtonTapped(label: "Buy"))
        }
        checkout.end()
        await tracker.finish()
        try await sut.test(.live) { client in
            let port = try #require(client.port)
            let endpoint = try #require(URL(string: "http://localhost:\(port)/batches"))
            let app = HTTPDestination(endpoint: endpoint, instrument: NoOpInstrument(), encoder: EventNamesEncoder())
            try await tracker.records.batch().deliver(to: app).execute()
        }

        let actual = try #require(serverTracer.finishedSpans.first { $0.operationName == "POST /batches" })
        #expect(actual.traceID == expectedTraceID)
        #expect(actual.spanContext.parentSpanID == nil)
    }

    @Test("The batches route answers 204 No Content")
    func noContent() async throws {
        let sut = Application(router: buildRouter())
        let expected = HTTPResponse.Status.noContent

        let actual = try await sut.test(.router) { client in
            try await client.execute(uri: "/batches", method: .post, body: ByteBuffer(string: "ButtonTapped")) { response in
                response.status
            }
        }

        #expect(actual == expected)
    }
}
