import Clocks
import Destinations
import Events
import Foundation
import HTTPDestinations
import HTTPTypes
import InMemoryTracing
import Instrumentation
import Synchronization
import Testing
import Trackers
import Tracing

@Suite("HTTPDestination's trace context", .timeLimit(.minutes(1)))
struct HTTPDestinationTraceContextTests {
    struct SignedUp: Event {
        var plan: String
    }

    /// Encodes the plans of a batch's sign-ups, comma separated, as plain text.
    struct PlansEncoder: BatchEncoder {
        static let transientStatuses: Set<TransientStatus> = []

        func requests(for batch: [EventRecord]) -> BatchRequests<Never> {
            BatchRequests(requests: [EncodedRequest(body: body(of: batch), recordIDs: batch.map(\.id))], skippedRecords: [])
        }

        func body(of batch: [EventRecord]) -> EncodedBatch {
            let plans = batch.map { ($0.event as? SignedUp)?.plan ?? "?" }
            return EncodedBatch(body: Data(plans.joined(separator: ",").utf8), contentType: "text/plain")
        }
    }

    struct SentRequest: Sendable {
        var request: HTTPRequest
        var body: Data
    }

    /// Answers every request with 200 OK, and keeps each request it was sent.
    final class TransportDouble: HTTPTransport {
        let sent = Mutex<[SentRequest]>([])

        func send(_ request: HTTPRequest, body: Data) async throws(HTTPTransportError) -> HTTPResponse {
            sent.withLock { $0.append(SentRequest(request: request, body: body)) }
            return HTTPResponse(status: .ok)
        }
    }

    /// Injects the same keys and values into every carrier, whatever the context.
    struct FixedInstrument: Instrument {
        var values: [(key: String, value: String)]

        func extract<Carrier, Extract: Extractor>(
            _ carrier: Carrier,
            into context: inout ServiceContext,
            using extractor: Extract
        ) where Extract.Carrier == Carrier {}

        func inject<Carrier, Inject: Injector>(
            _ context: ServiceContext,
            into carrier: inout Carrier,
            using injector: Inject
        ) where Inject.Carrier == Carrier {
            for (key, value) in values {
                injector.inject(value, forKey: key, into: &carrier)
            }
        }
    }

    @Test("The instrument injects the batch's first record's trace context into the header fields the transport receives")
    func firstRecordContext() async throws {
        let endpoint = try #require(URL(string: "https://collector.example.com/batches"))
        let tracer = InMemoryTracer()
        let transport = TransportDouble()
        let sut = HTTPDestination(endpoint: endpoint, instrument: tracer, transport: transport, encoder: PlansEncoder())
        let tracker = Tracker()
        let checkout = tracer.startSpan("checkout")
        let settings = tracer.startSpan("settings")
        let traceIDName = try #require(HTTPField.Name(InMemoryTracer.traceIDKey))
        let spanIDName = try #require(HTTPField.Name(InMemoryTracer.spanIDKey))
        let expectedTraceID = checkout.traceID
        let expectedSpanID = checkout.spanID
        let expectedInjections = 1

        ServiceContext.withValue(checkout.context) {
            tracker.track(SignedUp(plan: "a"))
        }
        ServiceContext.withValue(settings.context) {
            tracker.track(SignedUp(plan: "b"))
        }
        await tracker.finish()
        try await tracker.records.batch(strategy: .count(2)).deliver(to: sut).execute()
        checkout.end()
        settings.end()

        let actual = try #require(transport.sent.withLock { $0.first }).request.headerFields
        #expect(checkout.traceID != settings.traceID)
        #expect(actual[traceIDName] == expectedTraceID)
        #expect(actual[spanIDName] == expectedSpanID)
        #expect(tracer.performedContextInjections.count == expectedInjections)
    }

    @Test("With no instrument bootstrapped, a request carries only the configured fields and the content type, and is delivered as before")
    func noInstrument() async throws {
        let endpoint = try #require(URL(string: "https://collector.example.com/batches"))
        let tracer = InMemoryTracer()
        let transport = TransportDouble()
        let configured: HTTPFields = [.authorization: "Bearer t"]
        let sut = HTTPDestination(endpoint: endpoint, headerFields: configured, transport: transport, encoder: PlansEncoder())
        let span = tracer.startSpan("checkout")
        let batch = [EventRecord(event: SignedUp(plan: "a"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil, context: span.context)]
        let expectedFields: HTTPFields = [.authorization: "Bearer t", .contentType: "text/plain"]
        let expectedBody = Data("a".utf8)

        let outcome = await sut.send(EncodedRequest(body: PlansEncoder().body(of: batch), recordIDs: batch.map(\.id)), context: batch[0].context)
        span.end()

        let actual = try #require(transport.sent.withLock { $0.first })
        guard case .delivered = outcome else {
            Issue.record("Expected delivered, got \(outcome)")
            return
        }
        #expect(actual.request.headerFields == expectedFields)
        #expect(actual.body == expectedBody)
    }

    @Test("NoOpInstrument adds no header fields")
    func noOpInstrument() async throws {
        let endpoint = try #require(URL(string: "https://collector.example.com/batches"))
        let tracer = InMemoryTracer()
        let transport = TransportDouble()
        let sut = HTTPDestination(endpoint: endpoint, instrument: NoOpInstrument(), transport: transport, encoder: PlansEncoder())
        let span = tracer.startSpan("checkout")
        let batch = [EventRecord(event: SignedUp(plan: "a"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil, context: span.context)]
        let expected: HTTPFields = [.contentType: "text/plain"]

        await sut.receive(batch)
        span.end()

        let actual = try #require(transport.sent.withLock { $0.first }).request.headerFields
        #expect(actual == expected)
    }

    @Test("A first record tracked outside any span adds no header fields")
    func noSpan() async throws {
        let endpoint = try #require(URL(string: "https://collector.example.com/batches"))
        let tracer = InMemoryTracer()
        let transport = TransportDouble()
        let sut = HTTPDestination(endpoint: endpoint, instrument: tracer, transport: transport, encoder: PlansEncoder())
        let batch = [EventRecord(event: SignedUp(plan: "a"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)]
        let expected: HTTPFields = [.contentType: "text/plain"]

        await sut.receive(batch)

        let actual = try #require(transport.sent.withLock { $0.first }).request.headerFields
        #expect(actual == expected)
    }

    @Test("An injected field replaces a configured field of the same name, and the other configured fields stay")
    func injectedReplacesConfigured() async throws {
        let endpoint = try #require(URL(string: "https://collector.example.com/batches"))
        let tracer = InMemoryTracer()
        let transport = TransportDouble()
        let traceIDName = try #require(HTTPField.Name(InMemoryTracer.traceIDKey))
        let spanIDName = try #require(HTTPField.Name(InMemoryTracer.spanIDKey))
        let configured: HTTPFields = [.authorization: "Bearer t", traceIDName: "stale"]
        let sut = HTTPDestination(endpoint: endpoint, headerFields: configured, instrument: tracer, transport: transport, encoder: PlansEncoder())
        let span = tracer.startSpan("checkout")
        let batch = [EventRecord(event: SignedUp(plan: "a"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil, context: span.context)]
        let expected: HTTPFields = [.authorization: "Bearer t", traceIDName: span.traceID, spanIDName: span.spanID, .contentType: "text/plain"]

        await sut.receive(batch)
        span.end()

        let actual = try #require(transport.sent.withLock { $0.first }).request.headerFields
        #expect(actual == expected)
    }

    @Test("The encoder's content type replaces one the instrument injects")
    func contentTypeWins() async throws {
        let endpoint = try #require(URL(string: "https://collector.example.com/batches"))
        let transport = TransportDouble()
        let instrument = FixedInstrument(values: [("content-type", "application/octet-stream"), ("traceparent", "00-1-2-01")])
        let sut = HTTPDestination(endpoint: endpoint, instrument: instrument, transport: transport, encoder: PlansEncoder())
        let batch = [EventRecord(event: SignedUp(plan: "a"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)]
        let traceparent = try #require(HTTPField.Name("traceparent"))
        let expected: HTTPFields = [traceparent: "00-1-2-01", .contentType: "text/plain"]

        await sut.receive(batch)

        let actual = try #require(transport.sent.withLock { $0.first }).request.headerFields
        #expect(actual == expected)
    }

    @Test("A key that isn't a valid field name is left out, and the valid ones are sent")
    func invalidFieldName() async throws {
        let endpoint = try #require(URL(string: "https://collector.example.com/batches"))
        let transport = TransportDouble()
        let instrument = FixedInstrument(values: [("not a name", "x"), ("tracestate", "a=b")])
        let sut = HTTPDestination(endpoint: endpoint, instrument: instrument, transport: transport, encoder: PlansEncoder())
        let batch = [EventRecord(event: SignedUp(plan: "a"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)]
        let tracestate = try #require(HTTPField.Name("tracestate"))
        let expected: HTTPFields = [tracestate: "a=b", .contentType: "text/plain"]

        await sut.receive(batch)

        let actual = try #require(transport.sent.withLock { $0.first }).request.headerFields
        #expect(actual == expected)
    }

    @Test("An empty batch is sent without injecting any context")
    func emptyBatch() async throws {
        let endpoint = try #require(URL(string: "https://collector.example.com/batches"))
        let tracer = InMemoryTracer()
        let transport = TransportDouble()
        let sut = HTTPDestination(endpoint: endpoint, instrument: tracer, transport: transport, encoder: PlansEncoder())
        let expectedFields: HTTPFields = [.contentType: "text/plain"]

        await sut.receive([])

        let actual = try #require(transport.sent.withLock { $0.first }).request.headerFields
        #expect(actual == expectedFields)
        #expect(tracer.performedContextInjections.isEmpty)
    }

    @Test("The URLSession destination injects through the instrument it is given, and waits between attempts on the clock it is given")
    func urlSessionInstrument() async throws {
        // Port 1 on the loopback interface has no listener, so the send fails at once, after
        // the context was injected, and the destination waits on its clock to send again.
        let endpoint = try #require(URL(string: "http://127.0.0.1:1/batches"))
        let tracer = InMemoryTracer()
        let clock = TestClock()
        let sut = HTTPDestination(endpoint: endpoint, instrument: tracer, encoder: PlansEncoder(), clock: clock)
        let span = tracer.startSpan("checkout")
        let batch = [EventRecord(event: SignedUp(plan: "a"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil, context: span.context)]
        let expected = [span.traceID]
        let receiving = Task { await sut.receive(batch) }

        while (try? await clock.checkSuspension()) != nil {}
        receiving.cancel()
        await receiving.value
        span.end()

        let actual = tracer.performedContextInjections.compactMap { $0.values[InMemoryTracer.traceIDKey] }
        #expect(actual == expected)
    }
}
