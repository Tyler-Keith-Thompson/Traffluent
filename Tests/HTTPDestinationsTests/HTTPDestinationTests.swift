import Afluent
import DestinationTesting
import Destinations
import Events
import Foundation
import HTTPDestinations
import HTTPTypes
import Synchronization
import Testing
import Trackers

@Suite("HTTPDestination", .timeLimit(.minutes(1)))
struct HTTPDestinationTests {
    struct SignedUp: Event {
        var plan: String
    }

    /// Encodes the plans of a batch's sign-ups, comma separated, as plain text.
    struct PlansEncoder: BatchEncoder {
        func encode(_ batch: [EventRecord]) -> EncodedBatch {
            let plans = batch.map { ($0.event as? SignedUp)?.plan ?? "?" }
            return EncodedBatch(body: Data(plans.joined(separator: ",").utf8), contentType: "text/plain")
        }
    }

    struct Unencodable: Error, Equatable {}

    struct FailingEncoder: BatchEncoder {
        func encode(_ batch: [EventRecord]) throws(Unencodable) -> EncodedBatch {
            throw Unencodable()
        }
    }

    struct SentRequest: Sendable {
        var request: HTTPRequest
        var body: Data
    }

    /// Answers every request with `result`, and keeps each request it was sent.
    final class TransportDouble: HTTPTransport {
        let result: Result<HTTPResponse, HTTPTransportError>
        let sent = Mutex<[SentRequest]>([])

        init(_ result: Result<HTTPResponse, HTTPTransportError>) {
            self.result = result
        }

        func send(_ request: HTTPRequest, body: Data) async throws(HTTPTransportError) -> HTTPResponse {
            sent.withLock { $0.append(SentRequest(request: request, body: body)) }
            return try result.get()
        }
    }

    /// Says when a send starts, then waits for a response that never comes, noting whether the
    /// wait ended because the send was cancelled.
    final class GatedTransport: HTTPTransport {
        let started = SingleValueSubject<Void>()
        let response = SingleValueSubject<HTTPResponse>()
        let sawCancellation = Mutex(false)

        func send(_ request: HTTPRequest, body: Data) async throws(HTTPTransportError) -> HTTPResponse {
            try? started.send()
            do {
                return try await response.execute()
            } catch {
                sawCancellation.withLock { $0 = Task.isCancelled }
                throw .cancelled
            }
        }
    }

    @Test("Each batch is one POST to the endpoint, whose body is the encoder's for that batch")
    func requestPerBatch() async throws {
        let endpoint = try #require(URL(string: "https://collector.example.com/batches"))
        let transport = TransportDouble(.success(HTTPResponse(status: .ok)))
        let sut = HTTPDestination(endpoint: endpoint, transport: transport, encoder: PlansEncoder())
        let tracker = Tracker()
        let expectedMethods: [HTTPRequest.Method] = [.post, .post]
        let expectedURLs: [URL?] = [endpoint, endpoint]
        let expectedBodies = [Data("a".utf8), Data("b".utf8)]

        tracker.track(SignedUp(plan: "a"))
        tracker.track(SignedUp(plan: "b"))
        await tracker.finish()
        try await tracker.records.batch(strategy: .count(1)).deliver(to: sut).execute()

        let actual = transport.sent.withLock { $0 }
        #expect(actual.map(\.request.method) == expectedMethods)
        #expect(actual.map(\.request.url) == expectedURLs)
        #expect(actual.map(\.body) == expectedBodies)
    }

    @Test("A batch of several records is one request, its records encoded oldest first")
    func severalRecordsOneRequest() async throws {
        let endpoint = try #require(URL(string: "https://collector.example.com/batches"))
        let transport = TransportDouble(.success(HTTPResponse(status: .ok)))
        let sut = HTTPDestination(endpoint: endpoint, transport: transport, encoder: PlansEncoder())
        let tracker = Tracker()
        let expected = [Data("a,b,c".utf8)]

        for plan in ["a", "b", "c"] {
            tracker.track(SignedUp(plan: plan))
        }
        await tracker.finish()
        try await tracker.records.batch(strategy: .count(3)).deliver(to: sut).execute()

        let actual = transport.sent.withLock { $0.map(\.body) }
        #expect(actual == expected)
    }

    @Test("Every request carries the configured header fields, with the encoder's content type replacing a configured one")
    func headerFields() async throws {
        let endpoint = try #require(URL(string: "https://collector.example.com/batches"))
        let transport = TransportDouble(.success(HTTPResponse(status: .ok)))
        let configured: HTTPFields = [.authorization: "Bearer t", .contentType: "application/octet-stream"]
        let sut = HTTPDestination(endpoint: endpoint, headerFields: configured, transport: transport, encoder: PlansEncoder())
        let batch = [EventRecord(event: SignedUp(plan: "a"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: SourceLocation(file: "A.swift", fileID: "M/A.swift", function: "f()", line: 1, column: 1))]
        let expected: HTTPFields = [.authorization: "Bearer t", .contentType: "text/plain"]

        await sut.receive(batch)

        let actual = try #require(transport.sent.withLock { $0.first }).request.headerFields
        #expect(actual == expected)
    }

    @Test("A transport failure is handled inside receive: the delivery completes, the next batch is still sent, and another destination receives every batch")
    func transportFailure() async throws {
        let endpoint = try #require(URL(string: "https://collector.example.com/batches"))
        let transport = TransportDouble(.failure(.failed(reason: "offline")))
        let sut = HTTPDestination(endpoint: endpoint, transport: transport, encoder: PlansEncoder())
        let other = InMemoryDestination()
        let tracker = Tracker()
        let expectedAttempts = 2
        let expectedPlans = ["a", "b"]
        let expectedBatchCount = 2

        tracker.track(SignedUp(plan: "a"))
        tracker.track(SignedUp(plan: "b"))
        await tracker.finish()
        try await tracker.records.batch(strategy: .count(1)).deliver(to: sut, other).execute()

        let actualAttempts = transport.sent.withLock { $0.count }
        #expect(actualAttempts == expectedAttempts)
        #expect(other.batches.count == expectedBatchCount)
        #expect(other.events(of: SignedUp.self).map(\.plan) == expectedPlans)
    }

    @Test("A rejected batch doesn't stop the next one being sent")
    func rejectionCarriesOn() async throws {
        let endpoint = try #require(URL(string: "https://collector.example.com/batches"))
        let transport = TransportDouble(.success(HTTPResponse(status: .internalServerError)))
        let sut = HTTPDestination(endpoint: endpoint, transport: transport, encoder: PlansEncoder())
        let tracker = Tracker()
        let expected = [Data("a".utf8), Data("b".utf8)]

        tracker.track(SignedUp(plan: "a"))
        tracker.track(SignedUp(plan: "b"))
        await tracker.finish()
        try await tracker.records.batch(strategy: .count(1)).deliver(to: sut).execute()

        let actual = transport.sent.withLock { $0.map(\.body) }
        #expect(actual == expected)
    }

    @Test("A 2xx response, from 200 to 299, means the batch was delivered", arguments: [200, 204, 299])
    func delivered(code: Int) async throws {
        let endpoint = try #require(URL(string: "https://collector.example.com/batches"))
        let transport = TransportDouble(.success(HTTPResponse(status: .init(code: code))))
        let sut = HTTPDestination(endpoint: endpoint, transport: transport, encoder: PlansEncoder())
        let batch = [EventRecord(event: SignedUp(plan: "a"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: SourceLocation(file: "A.swift", fileID: "M/A.swift", function: "f()", line: 1, column: 1))]
        let expected = code

        let outcome = await sut.send(batch)

        guard case .delivered(let response) = outcome else {
            Issue.record("Expected delivered, got \(outcome)")
            return
        }
        let actual = response.status.code
        #expect(actual == expected)
    }

    @Test("A response outside 2xx means the batch was rejected", arguments: [199, 300, 404, 500])
    func rejected(code: Int) async throws {
        let endpoint = try #require(URL(string: "https://collector.example.com/batches"))
        let transport = TransportDouble(.success(HTTPResponse(status: .init(code: code))))
        let sut = HTTPDestination(endpoint: endpoint, transport: transport, encoder: PlansEncoder())
        let batch = [EventRecord(event: SignedUp(plan: "a"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: SourceLocation(file: "A.swift", fileID: "M/A.swift", function: "f()", line: 1, column: 1))]
        let expected = code

        let outcome = await sut.send(batch)

        guard case .rejected(let response) = outcome else {
            Issue.record("Expected rejected, got \(outcome)")
            return
        }
        let actual = response.status.code
        #expect(actual == expected)
    }

    @Test("A batch the encoder can't encode is not sent, and the outcome carries the encoder's error")
    func notEncoded() async throws {
        let endpoint = try #require(URL(string: "https://collector.example.com/batches"))
        let transport = TransportDouble(.success(HTTPResponse(status: .ok)))
        let sut = HTTPDestination(endpoint: endpoint, transport: transport, encoder: FailingEncoder())
        let batch = [EventRecord(event: SignedUp(plan: "a"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: SourceLocation(file: "A.swift", fileID: "M/A.swift", function: "f()", line: 1, column: 1))]
        let expectedAttempts = 0

        let outcome = await sut.send(batch)

        let actualAttempts = transport.sent.withLock { $0.count }
        guard case .notEncoded(let error) = outcome else {
            Issue.record("Expected notEncoded, got \(outcome)")
            return
        }
        #expect(error == Unencodable())
        #expect(actualAttempts == expectedAttempts)
    }

    @Test("A send that gets no response is not sent, and the outcome carries the transport's error")
    func notSent() async throws {
        let endpoint = try #require(URL(string: "https://collector.example.com/batches"))
        let expected = HTTPTransportError.failed(reason: "offline")
        let transport = TransportDouble(.failure(expected))
        let sut = HTTPDestination(endpoint: endpoint, transport: transport, encoder: PlansEncoder())
        let batch = [EventRecord(event: SignedUp(plan: "a"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: SourceLocation(file: "A.swift", fileID: "M/A.swift", function: "f()", line: 1, column: 1))]

        let outcome = await sut.send(batch)

        guard case .notSent(let actual) = outcome else {
            Issue.record("Expected notSent, got \(outcome)")
            return
        }
        #expect(actual == expected)
    }

    @Test("Cancelling the delivery's run cancels the send in flight, and receive returns")
    func cancellingDeliveryCancelsSend() async throws {
        let endpoint = try #require(URL(string: "https://collector.example.com/batches"))
        let transport = GatedTransport()
        let sut = HTTPDestination(endpoint: endpoint, transport: transport, encoder: PlansEncoder())
        let tracker = Tracker()
        let delivery = tracker.records.batch(strategy: .count(1)).deliver(to: sut)
        tracker.track(SignedUp(plan: "a"))
        let running = Task { try await delivery.execute() }
        try await transport.started.execute()

        running.cancel()
        // The delivery's task group waits for every destination's receive, so this returns only
        // once receive has.
        let result = await running.result

        let actual = transport.sawCancellation.withLock { $0 }
        #expect(actual)
        #expect(throws: CancellationError.self) { try result.get() }
    }

    @Test("A cancelled send's outcome is notSent(cancelled), and receive returns")
    func cancelledSendOutcome() async throws {
        let endpoint = try #require(URL(string: "https://collector.example.com/batches"))
        let transport = GatedTransport()
        let sut = HTTPDestination(endpoint: endpoint, transport: transport, encoder: PlansEncoder())
        let batch = [EventRecord(event: SignedUp(plan: "a"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: SourceLocation(file: "A.swift", fileID: "M/A.swift", function: "f()", line: 1, column: 1))]
        let sending = Task { await sut.send(batch) }
        try await transport.started.execute()

        sending.cancel()
        let outcome = await sending.value

        guard case .notSent(let actual) = outcome else {
            Issue.record("Expected notSent, got \(outcome)")
            return
        }
        #expect(actual == .cancelled)
    }
}
