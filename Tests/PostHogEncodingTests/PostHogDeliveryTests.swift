import Afluent
import Clocks
import Destinations
import EventMacros
import Foundation
import HTTPDestinations
import HTTPTypes
import Instrumentation
import Persistence
import PostHogEncoding
import Sessions
import Synchronization
import Testing
import Trackers
import TrackingPlans

@Suite("PostHogBatchEncoder through HTTPDestination", .timeLimit(.minutes(1)))
struct PostHogDeliveryTests {
    @Event(name: "checkout_started")
    struct CheckoutStarted {
        var cartSize: Int
    }

    /// An event named as one of PostHog's own.
    struct Identify: Event, Codable {
        static let name = "$identify"

        init() {}

    }

    enum TraceParentKey: ServiceContextKey {
        typealias Value = String
    }

    /// Injects a context's `TraceParentKey` as `traceparent`, as a W3C Trace Context tracer would.
    struct TraceParentInstrument: Instrument {
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
            if let traceParent = context[TraceParentKey.self] {
                injector.inject(traceParent, forKey: "traceparent", into: &carrier)
            }
        }
    }

    struct SentRequest: Sendable {
        var request: HTTPRequest
        var body: Data
    }

    /// Stands in for PostHog's capture endpoint: answers the nth request with the nth status of
    /// `script`, and every request past its end with its last; keeps each request, and announces
    /// each on `attempts`.
    final class PostHogStub: HTTPTransport {
        let script: [HTTPResponse.Status]
        let sent = Mutex<[SentRequest]>([])
        let (attempts, attempted) = AsyncStream.makeStream(of: Int.self)

        init(_ script: [HTTPResponse.Status]) {
            self.script = script
        }

        func send(_ request: HTTPRequest, body: Data) async throws(HTTPTransportError) -> HTTPResponse {
            let attempt = sent.withLock { sent in
                sent.append(SentRequest(request: request, body: body))
                return sent.count
            }
            attempted.yield(attempt)
            return HTTPResponse(status: script[min(attempt, script.count) - 1])
        }
    }

    @Test("A tracker's batch reaches the stub endpoint as one POST to /batch/ of the encoder's JSON, each event's distinct_id the session")
    func trackerToStub() async throws {
        let endpoint = try #require(URL(string: "https://posthog.example.com/batch/"))
        let encoder = PostHogBatchEncoder(projectToken: "phc_test", plan: try TrackingPlan(schemas: [CheckoutStarted.schema]))
        let stub = PostHogStub([.ok])
        let postHog = HTTPDestination(endpoint: endpoint, instrument: NoOpInstrument(), transport: stub, encoder: encoder)
        let memory = InMemoryDestination()
        let tracker = Tracker(enrichers: [.sessions(kinds: [])])
        let delivery = tracker.records.batch().deliver(to: postHog, memory)
        let expectedRequestCount = 1
        let expectedMethod = HTTPRequest.Method.post
        let expectedPath = "/batch/"
        let expectedContentType = "application/json"
        let expectedToken = "phc_test"

        tracker.track(CheckoutStarted(cartSize: 1))
        tracker.track(CheckoutStarted(cartSize: 2))
        await tracker.finish()
        try await delivery.execute()

        let sent = stub.sent.withLock { $0 }
        let actual = try #require(sent.first)
        let session = try #require(memory.records.first?.context[SessionKey.self])
        let expectedBody = try #require(encoder.requests(for: memory.records).requests.first).body.body
        let expectedDistinctIDs: [String?] = [session.uuidString.lowercased(), session.uuidString.lowercased()]
        let expectedUUIDs: [String?] = memory.records.map { $0.id.uuidString.lowercased() }
        let object = try #require(try JSONSerialization.jsonObject(with: actual.body) as? [String: Any])
        let events = try #require(object["batch"] as? [[String: Any]])
        let actualToken = object["api_key"] as? String
        let actualDistinctIDs = events.map { $0["distinct_id"] as? String }
        let actualUUIDs = events.map { $0["uuid"] as? String }
        #expect(sent.count == expectedRequestCount)
        #expect(actual.request.method == expectedMethod)
        #expect(actual.request.path == expectedPath)
        #expect(actual.request.headerFields[.contentType] == expectedContentType)
        #expect(actual.body == expectedBody)
        #expect(actualToken == expectedToken)
        #expect(actualDistinctIDs == expectedDistinctIDs)
        #expect(actualUUIDs == expectedUUIDs)
    }

    @Test("With NoOpInstrument the request carries no traceparent, which an injecting instrument would add")
    func noTraceContextHeader() async throws {
        let endpoint = try #require(URL(string: "https://posthog.example.com/batch/"))
        let encoder = PostHogBatchEncoder(projectToken: "phc_test", plan: try TrackingPlan(schemas: [CheckoutStarted.schema]))
        let traceParent = try #require(HTTPField.Name("traceparent"))
        var context = ServiceContext.topLevel
        context[SessionKey.self] = UUID()
        context[TraceParentKey.self] = "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
        let batch = [EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil, context: context)]
        let quiet = PostHogStub([.ok])
        let tracing = PostHogStub([.ok])
        let sut = HTTPDestination(endpoint: endpoint, instrument: NoOpInstrument(), transport: quiet, encoder: encoder)
        let injecting = HTTPDestination(endpoint: endpoint, instrument: TraceParentInstrument(), transport: tracing, encoder: encoder)
        let expectedInjected = "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"

        await sut.receive(batch)
        await injecting.receive(batch)

        let actual = try #require(quiet.sent.withLock { $0.first })
        let actualInjected = try #require(tracing.sent.withLock { $0.first })
        #expect(actual.request.headerFields[traceParent] == nil)
        #expect(actualInjected.request.headerFields[traceParent] == expectedInjected)
    }

    @Test("A batch the endpoint answers with 503 is sent again after the backoff's wait, with the same bytes, until it is answered with 200")
    func unavailableRetried() async throws {
        let endpoint = try #require(URL(string: "https://posthog.example.com/batch/"))
        let clock = TestClock()
        let encoder = PostHogBatchEncoder(projectToken: "phc_test", plan: try TrackingPlan(schemas: [CheckoutStarted.schema]))
        let stub = PostHogStub([.serviceUnavailable, .ok])
        let sut = HTTPDestination(endpoint: endpoint, instrument: NoOpInstrument(), transport: stub, encoder: encoder, clock: clock)
        var context = ServiceContext.topLevel
        context[SessionKey.self] = UUID()
        let batch = [EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil, context: context)]
        let expectedBody = try #require(encoder.requests(for: batch).requests.first).body.body
        var attempts = stub.attempts.makeAsyncIterator()
        let receiving = Task { await sut.receive(batch) }

        _ = await attempts.next()
        while (try? await clock.checkSuspension()) != nil {}
        await clock.advance(by: .seconds(1))
        await receiving.value

        let actual = stub.sent.withLock { $0.map(\.body) }
        #expect(actual == [expectedBody, expectedBody])
    }

    @Test("A recovered record, with no context, is sent under its own id rather than dropped")
    func recoveredRecordSent() async throws {
        let endpoint = try #require(URL(string: "https://posthog.example.com/batch/"))
        let encoder = PostHogBatchEncoder(projectToken: "phc_test", plan: try TrackingPlan(schemas: [CheckoutStarted.schema]))
        let stub = PostHogStub([.ok])
        let sut = HTTPDestination(endpoint: endpoint, instrument: NoOpInstrument(), transport: stub, encoder: encoder)
        let batch = [EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil, isRedelivered: true)]
        let expected: [String?] = [batch[0].id.uuidString.lowercased()]

        await sut.receive(batch)

        let body = try #require(stub.sent.withLock { $0.first }).body
        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let actual = (object["batch"] as? [[String: Any]] ?? []).map { $0["distinct_id"] as? String }
        #expect(actual == expected)
    }

    @Test("A batch of $-named events isn't sent, and each record is reported as skipped with reservedEventName")
    func reservedBatchReported() async throws {
        let endpoint = try #require(URL(string: "https://posthog.example.com/batch/"))
        let identify = EventSchema(name: "$identify", version: 1, consentCategory: .analytics, properties: [])
        let encoder = PostHogBatchEncoder(projectToken: "phc_test", plan: try TrackingPlan(schemas: [identify]))
        let stub = PostHogStub([.ok])
        let sut = HTTPDestination(endpoint: endpoint, instrument: NoOpInstrument(), transport: stub, encoder: encoder)
        let batch = [EventRecord(event: Identify(), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)]
        let expected = HTTPDropReport<PostHogEncodingError>.skipped(SkippedRecord(recordID: batch[0].id, eventName: "$identify", schemaVersion: 1, reason: .reservedEventName(name: "$identify")))

        await sut.receive(batch)

        var reports = sut.dropReports.makeAsyncIterator()
        let actual = await reports.next()
        let actualSent = stub.sent.withLock { $0 }
        #expect(actual == expected)
        #expect(actualSent.isEmpty)
    }
}
