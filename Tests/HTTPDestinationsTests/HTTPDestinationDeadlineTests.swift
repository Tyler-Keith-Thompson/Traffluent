import Afluent
import Clocks
import Events
import Foundation
import HTTPDestinations
import HTTPTypes
import Synchronization
import Testing

@Suite("HTTPDestination: request deadlines", .timeLimit(.minutes(1)))
struct HTTPDestinationDeadlineTests {
    struct SignedUp: Event {
        var plan: String
    }

    /// Encodes each record as a request of its own, its body the record's identifier, with the
    /// deadline `deadlines` gives the record's plan, if any.
    struct DeadlineEncoder: BatchEncoder {
        static let transientStatuses: Set<TransientStatus> = []

        static func outcome(of response: HTTPTransportResponse, for request: EncodedRequest) -> ResponseOutcome {
            .delivered
        }

        var deadlines: [String: Date] = [:]

        func requests(for batch: [EventRecord]) -> BatchRequests<Never> {
            let requests = batch.map { record in
                EncodedRequest(
                    body: EncodedBatch(body: Data(record.id.uuidString.utf8), contentType: "text/plain"),
                    recordIDs: [record.id],
                    deadline: (record.event as? SignedUp).flatMap { deadlines[$0.plan] })
            }
            return BatchRequests(requests: requests, skippedRecords: [])
        }
    }

    /// Answers the nth request with the nth result of `script`, and every request past its end
    /// with its last; notes when, on `clock`, each request was sent, and its body, and announces
    /// each on `attempts`.
    final class ScriptedTransport: HTTPTransport {
        let script: [Result<HTTPResponse, HTTPTransportError>]
        let clock: TestClock<Duration>
        let start: TestClock<Duration>.Instant
        let sentAt = Mutex<[Duration]>([])
        let bodies = Mutex<[Data]>([])
        let (attempts, attempted) = AsyncStream.makeStream(of: Int.self)

        init(_ script: [Result<HTTPResponse, HTTPTransportError>], clock: TestClock<Duration>) {
            self.script = script
            self.clock = clock
            start = clock.now
        }

        var attemptCount: Int {
            sentAt.withLock { $0.count }
        }

        func send(_ request: HTTPRequest, body: Data) async throws(HTTPTransportError) -> HTTPTransportResponse {
            let attempt = sentAt.withLock { sentAt in
                sentAt.append(start.duration(to: clock.now))
                return sentAt.count
            }
            bodies.withLock { $0.append(body) }
            attempted.yield(attempt)
            return try HTTPTransportResponse(head: script[min(attempt, script.count) - 1].get(), body: Data())
        }
    }

    /// A wall clock that reads `start` plus the time `clock` has advanced since it was made, so a
    /// test moves both by advancing the test clock.
    struct FollowingWallClock: Sendable {
        let start: Date
        let clock: TestClock<Duration>
        let origin: TestClock<Duration>.Instant

        init(start: Date, clock: TestClock<Duration>) {
            self.start = start
            self.clock = clock
            origin = clock.now
        }

        func now() -> Date {
            let elapsed = origin.duration(to: clock.now).components
            return start.addingTimeInterval(Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18)
        }
    }

    @Test("A request that keeps failing is sent no more once its deadline has passed, and is reported as deadlineExceeded with its deadline and records' identifiers")
    func failingUntilPastDeadline() async throws {
        let endpoint = try #require(URL(string: "https://collector.example.com/batches"))
        let clock = TestClock()
        let wallClock = FollowingWallClock(start: Date(timeIntervalSince1970: 1_000_000), clock: clock)
        let deadline = Date(timeIntervalSince1970: 1_000_002.5)
        let transport = ScriptedTransport([.failure(.failed(reason: "offline"))], clock: clock)
        let sut = HTTPDestination(endpoint: endpoint, transport: transport, encoder: DeadlineEncoder(deadlines: ["a": deadline]), backoff: ExponentialBackoff(jitter: .none), clock: clock, now: wallClock.now)
        let batch = [EventRecord(event: SignedUp(plan: "a"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)]
        let expectedSentAt: [Duration] = [.zero, .seconds(1)]
        let expected = HTTPDropReport<Never>.deadlineExceeded(deadline: deadline, recordIDs: batch.map(\.id))
        var attempts = transport.attempts.makeAsyncIterator()
        let receiving = Task { await sut.receive(batch) }

        for wait in [Duration.seconds(1), .seconds(2)] {
            _ = await attempts.next()
            while (try? await clock.checkSuspension()) != nil {}
            await clock.advance(by: wait)
        }
        await receiving.value

        var reports = sut.dropReports.makeAsyncIterator()
        let actual = await reports.next()
        #expect(actual == expected)
        #expect(transport.sentAt.withLock { $0 } == expectedSentAt)
        await #expect(throws: Never.self) { try await clock.checkSuspension() }
    }

    @Test("A request is sent again when the wall clock reads exactly its deadline, and delivered")
    func sentAtDeadline() async throws {
        let endpoint = try #require(URL(string: "https://collector.example.com/batches"))
        let clock = TestClock()
        let wallClock = FollowingWallClock(start: Date(timeIntervalSince1970: 1_000_000), clock: clock)
        let transport = ScriptedTransport([.failure(.failed(reason: "offline")), .success(HTTPResponse(status: .ok))], clock: clock)
        let sut = HTTPDestination(endpoint: endpoint, transport: transport, encoder: DeadlineEncoder(), backoff: ExponentialBackoff(jitter: .none), clock: clock, now: wallClock.now)
        let batch = [EventRecord(event: SignedUp(plan: "a"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)]
        let request = EncodedRequest(body: EncodedBatch(body: Data("a".utf8), contentType: "text/plain"), recordIDs: batch.map(\.id), deadline: Date(timeIntervalSince1970: 1_000_001))
        let expectedSentAt: [Duration] = [.zero, .seconds(1)]
        var attempts = transport.attempts.makeAsyncIterator()
        let sending = Task { await sut.send(request, context: nil) }

        _ = await attempts.next()
        while (try? await clock.checkSuspension()) != nil {}
        await clock.advance(by: .seconds(1))
        let outcome = await sending.value

        guard case .delivered(let response) = outcome else {
            Issue.record("Expected delivered, got \(outcome)")
            return
        }
        #expect(response.status == .ok)
        #expect(transport.sentAt.withLock { $0 } == expectedSentAt)
    }

    @Test("A request whose deadline passes, by a millisecond, during the wait before an attempt is not sent again")
    func justPastDeadline() async throws {
        let endpoint = try #require(URL(string: "https://collector.example.com/batches"))
        let clock = TestClock()
        let wallClock = FollowingWallClock(start: Date(timeIntervalSince1970: 1_000_000), clock: clock)
        let transport = ScriptedTransport([.failure(.failed(reason: "offline")), .success(HTTPResponse(status: .ok))], clock: clock)
        let sut = HTTPDestination(endpoint: endpoint, transport: transport, encoder: DeadlineEncoder(), backoff: ExponentialBackoff(jitter: .none), clock: clock, now: wallClock.now)
        let batch = [EventRecord(event: SignedUp(plan: "a"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)]
        let deadline = Date(timeIntervalSince1970: 1_000_000.999)
        let request = EncodedRequest(body: EncodedBatch(body: Data("a".utf8), contentType: "text/plain"), recordIDs: batch.map(\.id), deadline: deadline)
        let expectedAttempts = 1
        var attempts = transport.attempts.makeAsyncIterator()
        let sending = Task { await sut.send(request, context: nil) }

        _ = await attempts.next()
        while (try? await clock.checkSuspension()) != nil {}
        await clock.advance(by: .seconds(1))
        let outcome = await sending.value

        guard case .deadlineExceeded(let actual) = outcome else {
            Issue.record("Expected deadlineExceeded, got \(outcome)")
            return
        }
        #expect(actual == deadline)
        #expect(transport.attemptCount == expectedAttempts)
    }

    @Test("A request whose deadline has passed before its first attempt is never sent, and is reported")
    func pastDeadlineBeforeFirstAttempt() async throws {
        let endpoint = try #require(URL(string: "https://collector.example.com/batches"))
        let clock = TestClock()
        let deadline = Date(timeIntervalSince1970: 999_999.999)
        let transport = ScriptedTransport([.success(HTTPResponse(status: .ok))], clock: clock)
        let sut = HTTPDestination(endpoint: endpoint, transport: transport, encoder: DeadlineEncoder(deadlines: ["a": deadline]), clock: clock, now: { Date(timeIntervalSince1970: 1_000_000) })
        let batch = [EventRecord(event: SignedUp(plan: "a"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)]
        let expected = HTTPDropReport<Never>.deadlineExceeded(deadline: deadline, recordIDs: batch.map(\.id))

        await sut.receive(batch)

        var reports = sut.dropReports.makeAsyncIterator()
        let actual = await reports.next()
        #expect(actual == expected)
        #expect(transport.attemptCount == 0)
    }

    @Test("A request whose deadline the wall clock reads exactly is sent the first time")
    func firstAttemptAtDeadline() async throws {
        let endpoint = try #require(URL(string: "https://collector.example.com/batches"))
        let clock = TestClock()
        let transport = ScriptedTransport([.success(HTTPResponse(status: .ok))], clock: clock)
        let sut = HTTPDestination(endpoint: endpoint, transport: transport, encoder: DeadlineEncoder(), clock: clock, now: { Date(timeIntervalSince1970: 1_000_000) })
        let request = EncodedRequest(body: EncodedBatch(body: Data("a".utf8), contentType: "text/plain"), recordIDs: [UUID()], deadline: Date(timeIntervalSince1970: 1_000_000))
        let expectedAttempts = 1

        let outcome = await sut.send(request, context: nil)

        guard case .delivered = outcome else {
            Issue.record("Expected delivered, got \(outcome)")
            return
        }
        #expect(transport.attemptCount == expectedAttempts)
    }

    @Test("A request with a deadline is not sent, and is reported, while the wall clock reads NaN")
    func nanWallClock() async throws {
        let endpoint = try #require(URL(string: "https://collector.example.com/batches"))
        let clock = TestClock()
        let deadline = Date(timeIntervalSince1970: 1_000_000)
        let transport = ScriptedTransport([.success(HTTPResponse(status: .ok))], clock: clock)
        let sut = HTTPDestination(endpoint: endpoint, transport: transport, encoder: DeadlineEncoder(deadlines: ["a": deadline]), clock: clock, now: { Date(timeIntervalSince1970: .nan) })
        let batch = [EventRecord(event: SignedUp(plan: "a"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)]
        let expected = HTTPDropReport<Never>.deadlineExceeded(deadline: deadline, recordIDs: batch.map(\.id))

        await sut.receive(batch)

        var reports = sut.dropReports.makeAsyncIterator()
        let actual = await reports.next()
        #expect(actual == expected)
        #expect(transport.attemptCount == 0)
    }

    @Test("A request without a deadline is retried and delivered however late the wall clock reads, and isn't reported")
    func noDeadline() async throws {
        let endpoint = try #require(URL(string: "https://collector.example.com/batches"))
        let clock = TestClock()
        // The first request fails once and is then delivered; the second is rejected, so its
        // report is the first unless the first request was reported before it.
        let transport = ScriptedTransport([.failure(.failed(reason: "offline")), .success(HTTPResponse(status: .ok)), .success(HTTPResponse(status: .badRequest))], clock: clock)
        let sut = HTTPDestination(endpoint: endpoint, transport: transport, encoder: DeadlineEncoder(), backoff: ExponentialBackoff(jitter: .none), clock: clock, now: { .distantFuture })
        let batch = [
            EventRecord(event: SignedUp(plan: "a"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil),
            EventRecord(event: SignedUp(plan: "b"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil),
        ]
        let expectedSentAt: [Duration] = [.zero, .seconds(1), .seconds(1)]
        let expected = HTTPDropReport<Never>.rejected(status: .badRequest, recordIDs: [batch[1].id])
        var attempts = transport.attempts.makeAsyncIterator()
        let receiving = Task { await sut.receive(batch) }

        _ = await attempts.next()
        while (try? await clock.checkSuspension()) != nil {}
        await clock.advance(by: .seconds(1))
        await receiving.value

        var reports = sut.dropReports.makeAsyncIterator()
        let actual = await reports.next()
        #expect(actual == expected)
        #expect(transport.sentAt.withLock { $0 } == expectedSentAt)
    }

    /// Fails every request as `failure` says, and sets `wallClock` to `after` while it is in flight,
    /// as though the send took that long.
    final class SlowFailingTransport: HTTPTransport {
        let failure: Result<HTTPResponse, HTTPTransportError>
        let wallClock: SetWallClock
        let after: Date
        let sendCount = Mutex(0)

        init(_ failure: Result<HTTPResponse, HTTPTransportError>, wallClock: SetWallClock, after: Date) {
            self.failure = failure
            self.wallClock = wallClock
            self.after = after
        }

        func send(_ request: HTTPRequest, body: Data) async throws(HTTPTransportError) -> HTTPTransportResponse {
            sendCount.withLock { $0 += 1 }
            wallClock.reading.withLock { $0 = after }
            return try HTTPTransportResponse(head: failure.get(), body: Data())
        }
    }

    @Test("A send that fails once the deadline has passed, or while the wall clock reads NaN, is reported at once, without a backoff slept first", arguments: [
        (Result<HTTPResponse, HTTPTransportError>.failure(.failed(reason: "timed out")), 1_000_001.001),
        (.failure(.cancelled), 1_000_001.001),
        (.success(HTTPResponse(status: .serviceUnavailable)), 1_000_001.001),
        (.failure(.failed(reason: "timed out")), .nan),
    ])
    func failingPastDeadline(failure: Result<HTTPResponse, HTTPTransportError>, after: TimeInterval) async throws {
        let endpoint = try #require(URL(string: "https://collector.example.com/batches"))
        let clock = TestClock()
        let deadline = Date(timeIntervalSince1970: 1_000_001)
        let wallClock = SetWallClock(Date(timeIntervalSince1970: 1_000_000))
        let transport = SlowFailingTransport(failure, wallClock: wallClock, after: Date(timeIntervalSince1970: after))
        let sut = HTTPDestination(endpoint: endpoint, transport: transport, encoder: DeadlineEncoder(deadlines: ["a": deadline]), clock: clock, now: wallClock.now)
        let batch = [EventRecord(event: SignedUp(plan: "a"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)]
        let expected = HTTPDropReport<Never>.deadlineExceeded(deadline: deadline, recordIDs: batch.map(\.id))
        let expectedSendCount = 1

        // Nothing advances the test clock, so a backoff slept here would never end.
        await sut.receive(batch)

        var reports = sut.dropReports.makeAsyncIterator()
        let actual = await reports.next()
        #expect(actual == expected)
        #expect(transport.sendCount.withLock { $0 } == expectedSendCount)
        await #expect(throws: Never.self) { try await clock.checkSuspension() }
    }

    @Test("A send that fails at exactly its deadline is retried after the backoff, not reported")
    func failingAtDeadline() async throws {
        let endpoint = try #require(URL(string: "https://collector.example.com/batches"))
        let clock = TestClock()
        let deadline = Date(timeIntervalSince1970: 1_000_001)
        let wallClock = SetWallClock(Date(timeIntervalSince1970: 1_000_000))
        let transport = SlowFailingTransport(.failure(.failed(reason: "timed out")), wallClock: wallClock, after: deadline)
        let sut = HTTPDestination(endpoint: endpoint, transport: transport, encoder: DeadlineEncoder(deadlines: ["a": deadline]), clock: clock, now: wallClock.now)
        let request = EncodedRequest(body: EncodedBatch(body: Data("a".utf8), contentType: "text/plain"), recordIDs: [UUID()], deadline: deadline)
        let expectedSendCount = 1
        let sending = Task { await sut.send(request, context: nil) }
        // Waits until the destination sleeps on the backoff, which a report wouldn't.
        while (try? await clock.checkSuspension()) != nil {}

        sending.cancel()
        let outcome = await sending.value

        guard case .cancelled = outcome else {
            Issue.record("Expected cancelled during the backoff, got \(outcome)")
            return
        }
        #expect(transport.sendCount.withLock { $0 } == expectedSendCount)
    }

    @Test("Of a batch's requests, the one past its deadline is dropped and the next is still sent")
    func laterRequestsSent() async throws {
        let endpoint = try #require(URL(string: "https://collector.example.com/batches"))
        let clock = TestClock()
        let deadline = Date(timeIntervalSince1970: 999_999)
        let transport = ScriptedTransport([.success(HTTPResponse(status: .ok))], clock: clock)
        let sut = HTTPDestination(endpoint: endpoint, transport: transport, encoder: DeadlineEncoder(deadlines: ["a": deadline]), clock: clock, now: { Date(timeIntervalSince1970: 1_000_000) })
        let batch = [
            EventRecord(event: SignedUp(plan: "a"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil),
            EventRecord(event: SignedUp(plan: "b"), timestamp: Date(timeIntervalSince1970: 1), sourceLocation: nil),
        ]
        let expectedBodies = [Data(batch[1].id.uuidString.utf8)]
        let expected = HTTPDropReport<Never>.deadlineExceeded(deadline: deadline, recordIDs: [batch[0].id])

        await sut.receive(batch)

        var reports = sut.dropReports.makeAsyncIterator()
        let actual = await reports.next()
        #expect(actual == expected)
        #expect(transport.bodies.withLock { $0 } == expectedBodies)
    }

    @Test("The URLSession destination reads the wall clock it is given before the first attempt")
    func urlSessionWallClock() async throws {
        // A scheme URLSession refuses at once, so a request that got past the deadline check would
        // come back invalidRequest without reaching any network.
        let endpoint = try #require(URL(string: "foo://collector.example.com/batches"))
        let sut = HTTPDestination(endpoint: endpoint, encoder: DeadlineEncoder(), now: { .distantFuture })
        let deadline = Date(timeIntervalSince1970: 32_503_680_000)
        let request = EncodedRequest(body: EncodedBatch(body: Data("a".utf8), contentType: "text/plain"), recordIDs: [UUID()], deadline: deadline)

        let outcome = await sut.send(request, context: nil)

        guard case .deadlineExceeded(let actual) = outcome else {
            Issue.record("Expected deadlineExceeded, got \(outcome)")
            return
        }
        #expect(actual == deadline)
    }

    /// A wall clock the test sets.
    final class SetWallClock: Sendable {
        let reading: Mutex<Date>

        init(_ reading: Date) {
            self.reading = Mutex(reading)
        }

        func now() -> Date {
            reading.withLock { $0 }
        }
    }

    /// A clock whose sleep says it started, then returns once its task is cancelled, as though
    /// the wait had ended, rather than throwing.
    final class CancellationIgnoringClock: Clock {
        let sleeping = SingleValueSubject<Void>()
        let released = SingleValueSubject<Void>()

        var now: ContinuousClock.Instant { ContinuousClock().now }
        var minimumResolution: Duration { .zero }

        func sleep(until deadline: ContinuousClock.Instant, tolerance: Duration?) async throws {
            try? sleeping.send()
            _ = try? await released.execute()
        }
    }

    @Test("A delivery cancelled during the wait before an attempt is cancelled, not reported, though the deadline passed meanwhile and the clock's sleep ignored the cancellation")
    func cancelledPastDeadline() async throws {
        let endpoint = try #require(URL(string: "https://collector.example.com/batches"))
        let clock = TestClock()
        let sleepClock = CancellationIgnoringClock()
        let wallClock = SetWallClock(Date(timeIntervalSince1970: 1_000_000))
        let transport = ScriptedTransport([.failure(.failed(reason: "offline")), .success(HTTPResponse(status: .badRequest))], clock: clock)
        let sut = HTTPDestination(endpoint: endpoint, transport: transport, encoder: DeadlineEncoder(), clock: sleepClock, now: wallClock.now)
        let batch = [EventRecord(event: SignedUp(plan: "a"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)]
        let request = EncodedRequest(body: EncodedBatch(body: Data("a".utf8), contentType: "text/plain"), recordIDs: batch.map(\.id), deadline: Date(timeIntervalSince1970: 1_000_001))
        let sending = Task { await sut.send(request, context: nil) }
        try await sleepClock.sleeping.execute()
        wallClock.reading.withLock { $0 = Date(timeIntervalSince1970: 1_000_002) }

        sending.cancel()
        let outcome = await sending.value

        guard case .cancelled = outcome else {
            Issue.record("Expected cancelled, got \(outcome)")
            return
        }
    }
}
