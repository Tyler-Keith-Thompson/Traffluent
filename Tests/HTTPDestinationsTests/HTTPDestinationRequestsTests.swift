import Afluent
import Events
import Foundation
import HTTPDestinations
import HTTPTypes
import Instrumentation
import Synchronization
import Testing

@Suite("HTTPDestination: a batch of several requests", .timeLimit(.minutes(1)))
struct HTTPDestinationRequestsTests {
    struct SignedUp: Event {
        var plan: String
    }

    struct Unencodable: Error, Hashable {
        var plan: String
    }

    /// A request per record, its plan as the body, leaving out a record whose plan is "skip".
    struct PerRecordEncoder: BatchEncoder {
        static let transientStatuses: Set<TransientStatus> = []

        typealias Failure = Unencodable

        func requests(for batch: [EventRecord]) -> BatchRequests<Unencodable> {
            BatchRequests(
                requests: batch.filter { $0.plan != "skip" }.map { EncodedRequest(body: EncodedBatch(body: Data($0.plan.utf8), contentType: "text/plain"), recordIDs: [$0.id]) },
                skippedRecords: batch.filter { $0.plan == "skip" }.map { SkippedRecord(recordID: $0.id, eventName: $0.name, schemaVersion: 1, reason: Unencodable(plan: $0.plan)) }
            )
        }
    }

    /// Answers each request whose body is in `rejecting` with 400 and every other with 200, and
    /// keeps each request it was sent.
    final class TransportDouble: HTTPTransport {
        let rejecting: Set<String>
        let sent = Mutex<[(request: HTTPRequest, body: String)]>([])

        init(rejecting: Set<String> = []) {
            self.rejecting = rejecting
        }

        func send(_ request: HTTPRequest, body: Data) async throws(HTTPTransportError) -> HTTPResponse {
            let text = String(decoding: body, as: UTF8.self)
            sent.withLock { $0.append((request, text)) }
            return HTTPResponse(status: rejecting.contains(text) ? .badRequest : .ok)
        }
    }

    /// Answers a request whose body is in `failingOnce` with 503 the first time, and every other
    /// with 200, and keeps each request it was sent.
    final class FlakyTransport: HTTPTransport {
        let failingOnce: Set<String>
        let sent = Mutex<[String]>([])

        init(failingOnce: Set<String>) {
            self.failingOnce = failingOnce
        }

        func send(_ request: HTTPRequest, body: Data) async throws(HTTPTransportError) -> HTTPResponse {
            let text = String(decoding: body, as: UTF8.self)
            let isFirst = sent.withLock { sent in
                defer { sent.append(text) }
                return !sent.contains(text)
            }
            return HTTPResponse(status: isFirst && failingOnce.contains(text) ? .serviceUnavailable : .ok)
        }
    }

    /// Answers 200 at once, but for a request whose body is `gated`: says when it starts, then
    /// waits for a response that never comes, until it is cancelled.
    final class GatedTransport: HTTPTransport {
        let gated: String
        let started = SingleValueSubject<Void>()
        let response = SingleValueSubject<HTTPResponse>()
        let sent = Mutex<[String]>([])

        init(gated: String) {
            self.gated = gated
        }

        func send(_ request: HTTPRequest, body: Data) async throws(HTTPTransportError) -> HTTPResponse {
            let text = String(decoding: body, as: UTF8.self)
            sent.withLock { $0.append(text) }
            guard text == gated else { return HTTPResponse(status: .ok) }
            try? started.send()
            do {
                return try await response.execute()
            } catch {
                throw .cancelled
            }
        }
    }

    /// Answers each request with no response, or 200 for a body in `answering`.
    final class OfflineTransport: HTTPTransport {
        let answering: Set<String>
        let sent = Mutex<[String]>([])

        init(answering: Set<String>) {
            self.answering = answering
        }

        func send(_ request: HTTPRequest, body: Data) async throws(HTTPTransportError) -> HTTPResponse {
            let text = String(decoding: body, as: UTF8.self)
            sent.withLock { $0.append(text) }
            guard answering.contains(text) else { throw .failed(reason: "offline") }
            return HTTPResponse(status: .ok)
        }
    }

    /// A clock whose every sleep throws `Failure`, as a caller's clock might.
    struct ThrowingClock: Clock {
        struct Failure: Error {}

        var now: ContinuousClock.Instant { ContinuousClock().now }
        var minimumResolution: Duration { .zero }

        func sleep(until deadline: ContinuousClock.Instant, tolerance: Duration?) async throws {
            throw Failure()
        }
    }

    /// Injects the context's plan, under "plan", into each request's header fields.
    struct PlanInstrument: Instrument {
        func extract<Carrier, Extract: Extractor>(_ carrier: Carrier, into context: inout ServiceContext, using extractor: Extract) where Extract.Carrier == Carrier {}

        func inject<Carrier, Inject: Injector>(_ context: ServiceContext, into carrier: inout Carrier, using injector: Inject) where Inject.Carrier == Carrier {
            if let plan = context[PlanKey.self] {
                injector.inject(plan, forKey: "plan", into: &carrier)
            }
        }
    }

    enum PlanKey: ServiceContextKey {
        typealias Value = String
    }

    @Test("Each request is sent in order, a record left out is reported as skipped, and nothing else is reported")
    func requestsInOrder() async throws {
        let endpoint = try #require(URL(string: "https://collector.example.com/batches"))
        let transport = TransportDouble()
        let sut = HTTPDestination(endpoint: endpoint, transport: transport, encoder: PerRecordEncoder())
        let batch = ["a", "skip", "b"].map { EventRecord(event: SignedUp(plan: $0), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil) }
        let expectedBodies = ["a", "b"]
        let expectedReport = HTTPDropReport<Unencodable>.skipped(SkippedRecord(recordID: batch[1].id, eventName: "SignedUp", schemaVersion: 1, reason: Unencodable(plan: "skip")))

        await sut.receive(batch)

        let actualBodies = transport.sent.withLock { $0.map(\.body) }
        var reports = sut.dropReports.makeAsyncIterator()
        let actualReport = await reports.next()
        #expect(actualBodies == expectedBodies)
        #expect(actualReport == expectedReport)
    }

    @Test("A rejected request is reported with its own records alone, and the requests after it are still sent")
    func rejectionPerRequest() async throws {
        let endpoint = try #require(URL(string: "https://collector.example.com/batches"))
        let transport = TransportDouble(rejecting: ["a"])
        let sut = HTTPDestination(endpoint: endpoint, transport: transport, encoder: PerRecordEncoder())
        let batch = ["a", "b"].map { EventRecord(event: SignedUp(plan: $0), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil) }
        let expectedBodies = ["a", "b"]
        let expectedReport = HTTPDropReport<Unencodable>.rejected(status: .badRequest, recordIDs: [batch[0].id])

        await sut.receive(batch)
        // A second, rejected batch: a report of the first batch's second request would come
        // before this one's.
        await sut.receive([EventRecord(event: SignedUp(plan: "a"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)])

        let actualBodies = Array(transport.sent.withLock { $0.map(\.body) }.prefix(2))
        var reports = sut.dropReports.makeAsyncIterator()
        let actualFirst = await reports.next()
        let actualSecond = await reports.next()
        #expect(actualBodies == expectedBodies)
        #expect(actualFirst == expectedReport)
        if case .rejected(.badRequest, _) = actualSecond {} else {
            Issue.record("Expected the second batch's rejection, got \(String(describing: actualSecond))")
        }
    }

    @Test("Each request carries the trace context of its own first record")
    func contextPerRequest() async throws {
        let endpoint = try #require(URL(string: "https://collector.example.com/batches"))
        let transport = TransportDouble()
        let sut = HTTPDestination(endpoint: endpoint, instrument: PlanInstrument(), transport: transport, encoder: PerRecordEncoder())
        let batch = ["a", "b"].map { plan in
            var context = ServiceContext.topLevel
            context[PlanKey.self] = "context-\(plan)"
            return EventRecord(event: SignedUp(plan: plan), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil, context: context)
        }
        let expected: [String?] = ["context-a", "context-b"]
        let field = try #require(HTTPField.Name("plan"))

        await sut.receive(batch)

        let actual = transport.sent.withLock { $0.map { $0.request.headerFields[field] } }
        #expect(actual == expected)
    }

    @Test("A batch whose every record is left out sends nothing")
    func everyRecordSkipped() async throws {
        let endpoint = try #require(URL(string: "https://collector.example.com/batches"))
        let transport = TransportDouble()
        let sut = HTTPDestination(endpoint: endpoint, transport: transport, encoder: PerRecordEncoder())
        let batch = [EventRecord(event: SignedUp(plan: "skip"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)]

        await sut.receive(batch)

        let actual = transport.sent.withLock { $0.count }
        #expect(actual == 0)
    }

    @Test("A request sent again after a transient failure is the only one sent again: the requests before it aren't")
    func retryResendsOneRequest() async throws {
        let endpoint = try #require(URL(string: "https://collector.example.com/batches"))
        let transport = FlakyTransport(failingOnce: ["b"])
        let backoff = try ExponentialBackoff(initialDelay: .nanoseconds(1), maximumDelay: .nanoseconds(1))
        let sut = HTTPDestination(endpoint: endpoint, transport: transport, encoder: PerRecordEncoder(), backoff: backoff)
        let batch = ["a", "b", "c"].map { EventRecord(event: SignedUp(plan: $0), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil) }
        let expected = ["a", "b", "b", "c"]

        await sut.receive(batch)

        let actual = transport.sent.withLock { $0 }
        #expect(actual == expected)
    }

    @Test("Cancelling the delivery during a batch's second request stops it: the later requests aren't sent, and nothing is reported")
    func cancelledMidBatch() async throws {
        let endpoint = try #require(URL(string: "https://collector.example.com/batches"))
        let transport = GatedTransport(gated: "b")
        let sut = HTTPDestination(endpoint: endpoint, transport: transport, encoder: PerRecordEncoder())
        let batch = ["a", "b", "c"].map { EventRecord(event: SignedUp(plan: $0), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil) }
        let rejected = [EventRecord(event: SignedUp(plan: "skip"), timestamp: Date(timeIntervalSince1970: 1), sourceLocation: nil)]
        let expectedBodies = ["a", "b"]
        let expectedReport = HTTPDropReport<Unencodable>.skipped(SkippedRecord(recordID: rejected[0].id, eventName: "SignedUp", schemaVersion: 1, reason: Unencodable(plan: "skip")))
        let receiving = Task { await sut.receive(batch) }
        try await transport.started.execute()

        receiving.cancel()
        await receiving.value

        let actualBodies = transport.sent.withLock { $0 }
        // A later batch whose record is skipped: a report of the cancelled batch would come first.
        await sut.receive(rejected)
        var reports = sut.dropReports.makeAsyncIterator()
        let actualReport = await reports.next()
        #expect(actualBodies == expectedBodies)
        #expect(actualReport == expectedReport)
    }

    @Test("A request given up on because the clock's wait threw is logged, not reported, and the batch's next request is sent")
    func abandonedCarriesOn() async throws {
        let endpoint = try #require(URL(string: "https://collector.example.com/batches"))
        let transport = OfflineTransport(answering: ["b"])
        let sut = HTTPDestination(endpoint: endpoint, transport: transport, encoder: PerRecordEncoder(), clock: ThrowingClock())
        let batch = ["a", "b"].map { EventRecord(event: SignedUp(plan: $0), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil) }
        let skipped = [EventRecord(event: SignedUp(plan: "skip"), timestamp: Date(timeIntervalSince1970: 1), sourceLocation: nil)]
        let expectedBodies = ["a", "b"]
        let expectedReport = HTTPDropReport<Unencodable>.skipped(SkippedRecord(recordID: skipped[0].id, eventName: "SignedUp", schemaVersion: 1, reason: Unencodable(plan: "skip")))

        await sut.receive(batch)

        let actualBodies = transport.sent.withLock { $0 }
        // A later batch whose record is skipped: a report of the abandoned request would come first.
        await sut.receive(skipped)
        var reports = sut.dropReports.makeAsyncIterator()
        let actualReport = await reports.next()
        #expect(actualBodies == expectedBodies)
        #expect(actualReport == expectedReport)
    }
}

extension EventRecord {
    fileprivate var plan: String {
        (event as? HTTPDestinationRequestsTests.SignedUp)?.plan ?? "?"
    }
}
