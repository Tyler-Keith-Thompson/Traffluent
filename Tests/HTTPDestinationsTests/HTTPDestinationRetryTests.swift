import Afluent
import Clocks
import Destinations
import Events
import Foundation
import HTTPDestinations
import HTTPTypes
import Synchronization
import Testing
import Trackers

@Suite("HTTPDestination: retries and drops", .timeLimit(.minutes(1)))
struct HTTPDestinationRetryTests {
    struct SignedUp: Event {
        var plan: String
    }

    /// Encodes a batch as its records' identifiers, one per line, as plain text.
    struct IdentifiersEncoder: BatchEncoder {
        func encode(_ batch: [EventRecord]) -> EncodedBatch {
            EncodedBatch(body: Data(batch.map(\.id.uuidString).joined(separator: "\n").utf8), contentType: "text/plain")
        }
    }

    struct Unencodable: Error, Equatable {}

    struct FailingEncoder: BatchEncoder {
        func encode(_ batch: [EventRecord]) throws(Unencodable) -> EncodedBatch {
            throw Unencodable()
        }
    }

    /// Answers the nth request with the nth result of `script`, and every request past its end
    /// with its last; notes when, on `clock`, each request was sent, and announces each on
    /// `attempts`.
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

        func send(_ request: HTTPRequest, body: Data) async throws(HTTPTransportError) -> HTTPResponse {
            let attempt = sentAt.withLock { sentAt in
                sentAt.append(start.duration(to: clock.now))
                return sentAt.count
            }
            bodies.withLock { $0.append(body) }
            attempted.yield(attempt)
            return try script[min(attempt, script.count) - 1].get()
        }
    }

    /// Says when a send starts, then waits for a response that never comes, noting whether the
    /// wait ended because the send was cancelled.
    final class GatedTransport: HTTPTransport {
        let started = SingleValueSubject<Void>()
        let response = SingleValueSubject<HTTPResponse>()
        let sawCancellation = Mutex(false)
        let attemptCount = Mutex(0)

        func send(_ request: HTTPRequest, body: Data) async throws(HTTPTransportError) -> HTTPResponse {
            attemptCount.withLock { $0 += 1 }
            try? started.send()
            do {
                return try await response.execute()
            } catch {
                sawCancellation.withLock { $0 = Task.isCancelled }
                throw .cancelled
            }
        }
    }

    @Test("A send that gets no response is sent again after each of the backoff's waits, on its clock, until one is answered with 2xx, and nothing is reported")
    func unansweredRetried() async throws {
        let endpoint = try #require(URL(string: "https://collector.example.com/batches"))
        let clock = TestClock()
        let transport = ScriptedTransport([.failure(.failed(reason: "offline")), .failure(.failed(reason: "offline")), .success(HTTPResponse(status: .ok))], clock: clock)
        let sut = HTTPDestination(endpoint: endpoint, transport: transport, encoder: IdentifiersEncoder(), clock: clock)
        let batch = [EventRecord(event: SignedUp(plan: "a"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)]
        let rejected = [EventRecord(event: SignedUp(plan: "b"), timestamp: Date(timeIntervalSince1970: 1), sourceLocation: nil)]
        let expectedSentAt: [Duration] = [.zero, .seconds(1), .seconds(3)]
        let expectedBodies = Array(repeating: Data(batch[0].id.uuidString.utf8), count: 3)
        var attempts = transport.attempts.makeAsyncIterator()
        let receiving = Task { await sut.receive(batch) }

        for wait in [Duration.seconds(1), .seconds(2)] {
            _ = await attempts.next()
            while (try? await clock.checkSuspension()) != nil {}
            await clock.advance(by: wait)
        }
        await receiving.value

        #expect(transport.sentAt.withLock { $0 } == expectedSentAt)
        #expect(transport.bodies.withLock { $0 } == expectedBodies)
        // A report of the retried batch would come before this one's.
        let rejecting = HTTPDestination(endpoint: endpoint, transport: ScriptedTransport([.success(HTTPResponse(status: .badRequest))], clock: clock), encoder: IdentifiersEncoder(), clock: clock)
        await rejecting.receive(rejected)
        var reports = rejecting.dropReports.makeAsyncIterator()
        let actual = await reports.next()
        #expect(actual == .rejected(status: .badRequest, recordIDs: rejected.map(\.id)))
    }

    @Test("A send answered with 5xx, 408 or 429 is sent again after the backoff's first wait, and delivered when answered with 2xx", arguments: [500, 503, 599, 408, 429])
    func transientStatusRetried(code: Int) async throws {
        let endpoint = try #require(URL(string: "https://collector.example.com/batches"))
        let clock = TestClock()
        let transport = ScriptedTransport([.success(HTTPResponse(status: .init(code: code))), .success(HTTPResponse(status: .noContent))], clock: clock)
        let sut = HTTPDestination(endpoint: endpoint, transport: transport, encoder: IdentifiersEncoder(), clock: clock)
        let batch = [EventRecord(event: SignedUp(plan: "a"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)]
        let expected: [Duration] = [.zero, .seconds(1)]
        var attempts = transport.attempts.makeAsyncIterator()
        let receiving = Task { await sut.send(batch) }

        _ = await attempts.next()
        while (try? await clock.checkSuspension()) != nil {}
        await clock.advance(by: .seconds(1))
        let outcome = await receiving.value

        guard case .delivered(let response) = outcome else {
            Issue.record("Expected delivered, got \(outcome)")
            return
        }
        #expect(response.status == .noContent)
        #expect(transport.sentAt.withLock { $0 } == expected)
    }

    @Test("A batch answered with 2xx the first time is sent once, without waiting")
    func deliveredFirstTime() async throws {
        let endpoint = try #require(URL(string: "https://collector.example.com/batches"))
        let clock = TestClock()
        let transport = ScriptedTransport([.success(HTTPResponse(status: .ok))], clock: clock)
        let sut = HTTPDestination(endpoint: endpoint, transport: transport, encoder: IdentifiersEncoder(), clock: clock)
        let batch = [EventRecord(event: SignedUp(plan: "a"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)]
        let expected = 1

        await sut.receive(batch)

        #expect(transport.attemptCount == expected)
        await #expect(throws: Never.self) { try await clock.checkSuspension() }
    }

    @Test("The waits are the default backoff's, 1 s doubling to 60 s and then 60 s each, each wait exactly that long on the clock")
    func defaultDelaySequence() async throws {
        let endpoint = try #require(URL(string: "https://collector.example.com/batches"))
        let clock = TestClock()
        let expectedWaits: [Duration] = [.seconds(1), .seconds(2), .seconds(4), .seconds(8), .seconds(16), .seconds(32), .seconds(60), .seconds(60), .seconds(60)]
        let failures = Array(repeating: Result<HTTPResponse, HTTPTransportError>.failure(.failed(reason: "offline")), count: expectedWaits.count)
        let transport = ScriptedTransport(failures + [.success(HTTPResponse(status: .ok))], clock: clock)
        let sut = HTTPDestination(endpoint: endpoint, transport: transport, encoder: IdentifiersEncoder(), clock: clock)
        let batch = [EventRecord(event: SignedUp(plan: "a"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)]
        var attempts = transport.attempts.makeAsyncIterator()
        let receiving = Task { await sut.receive(batch) }
        var earlyAttempts: [Int] = []

        for (attempt, wait) in zip(1..., expectedWaits) {
            _ = await attempts.next()
            while (try? await clock.checkSuspension()) != nil {}
            await clock.advance(by: wait - .nanoseconds(1))
            if transport.attemptCount != attempt { earlyAttempts.append(attempt) }
            await clock.advance(by: .nanoseconds(1))
        }
        await receiving.value

        let actual = transport.sentAt.withLock { sentAt in zip(sentAt.dropFirst(), sentAt).map { $0 - $1 } }
        #expect(earlyAttempts.isEmpty)
        #expect(actual == expectedWaits)
    }

    @Test("A given backoff sets the waits, and they stay at its maximum once doubling reaches it")
    func givenBackoffCapped() async throws {
        let endpoint = try #require(URL(string: "https://collector.example.com/batches"))
        let clock = TestClock()
        let backoff = try ExponentialBackoff(initialDelay: .milliseconds(300), maximumDelay: .seconds(1))
        let expectedWaits: [Duration] = [.milliseconds(300), .milliseconds(600), .seconds(1), .seconds(1)]
        let failures = Array(repeating: Result<HTTPResponse, HTTPTransportError>.success(HTTPResponse(status: .serviceUnavailable)), count: expectedWaits.count)
        let transport = ScriptedTransport(failures + [.success(HTTPResponse(status: .ok))], clock: clock)
        let sut = HTTPDestination(endpoint: endpoint, transport: transport, encoder: IdentifiersEncoder(), backoff: backoff, clock: clock)
        let batch = [EventRecord(event: SignedUp(plan: "a"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)]
        var attempts = transport.attempts.makeAsyncIterator()
        let receiving = Task { await sut.receive(batch) }

        for wait in expectedWaits {
            _ = await attempts.next()
            while (try? await clock.checkSuspension()) != nil {}
            await clock.advance(by: wait)
        }
        await receiving.value

        let actual = transport.sentAt.withLock { sentAt in zip(sentAt.dropFirst(), sentAt).map { $0 - $1 } }
        #expect(actual == expectedWaits)
    }

    @Test("Each batch's waits start again at the backoff's first, however many the batch before it took")
    func waitsStartOverPerBatch() async throws {
        let endpoint = try #require(URL(string: "https://collector.example.com/batches"))
        let clock = TestClock()
        let offline = Result<HTTPResponse, HTTPTransportError>.failure(.failed(reason: "offline"))
        let delivered = Result<HTTPResponse, HTTPTransportError>.success(HTTPResponse(status: .ok))
        let transport = ScriptedTransport([offline, offline, delivered, offline, delivered], clock: clock)
        let sut = HTTPDestination(endpoint: endpoint, transport: transport, encoder: IdentifiersEncoder(), clock: clock)
        let first = [EventRecord(event: SignedUp(plan: "a"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)]
        let second = [EventRecord(event: SignedUp(plan: "b"), timestamp: Date(timeIntervalSince1970: 1), sourceLocation: nil)]
        let expected: [Duration] = [.seconds(1), .seconds(2), .zero, .seconds(1)]
        var attempts = transport.attempts.makeAsyncIterator()
        let receiving = Task {
            await sut.receive(first)
            await sut.receive(second)
        }

        // The third attempt delivers the first batch, and the second batch's first is sent at once.
        for wait in expected {
            _ = await attempts.next()
            if wait > .zero {
                while (try? await clock.checkSuspension()) != nil {}
                await clock.advance(by: wait)
            }
        }
        await receiving.value

        let actual = transport.sentAt.withLock { sentAt in zip(sentAt.dropFirst(), sentAt).map { $0 - $1 } }
        #expect(actual == expected)
    }

    @Test("A batch answered with any other non-2xx status is sent once, dropped, and reported with that status and its records' identifiers", arguments: [199, 300, 400, 401, 404, 413, 422, 499])
    func rejectedReported(code: Int) async throws {
        let endpoint = try #require(URL(string: "https://collector.example.com/batches"))
        let clock = TestClock()
        let transport = ScriptedTransport([.success(HTTPResponse(status: .init(code: code))), .success(HTTPResponse(status: .ok))], clock: clock)
        let sut = HTTPDestination(endpoint: endpoint, transport: transport, encoder: IdentifiersEncoder(), clock: clock)
        let batch = [
            EventRecord(event: SignedUp(plan: "a"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil),
            EventRecord(event: SignedUp(plan: "b"), timestamp: Date(timeIntervalSince1970: 1), sourceLocation: nil),
        ]
        let expected = HTTPDropReport<Never>.rejected(status: .init(code: code), recordIDs: batch.map(\.id))
        let expectedAttempts = 1

        await sut.receive(batch)

        var reports = sut.dropReports.makeAsyncIterator()
        let actual = await reports.next()
        #expect(actual == expected)
        #expect(transport.attemptCount == expectedAttempts)
    }

    @Test("A batch whose request the transport can never send is sent once, dropped, and reported with the transport's reason and its records' identifiers")
    func invalidRequestReported() async throws {
        let endpoint = try #require(URL(string: "https://collector.example.com/batches"))
        let clock = TestClock()
        let transport = ScriptedTransport([.failure(.invalidRequest(reason: "NSURLErrorDomain -1002")), .success(HTTPResponse(status: .ok))], clock: clock)
        let sut = HTTPDestination(endpoint: endpoint, transport: transport, encoder: IdentifiersEncoder(), clock: clock)
        let batch = [EventRecord(event: SignedUp(plan: "a"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)]
        let expected = HTTPDropReport<Never>.invalidRequest(reason: "NSURLErrorDomain -1002", recordIDs: batch.map(\.id))
        let expectedAttempts = 1

        await sut.receive(batch)

        var reports = sut.dropReports.makeAsyncIterator()
        let actual = await reports.next()
        #expect(actual == expected)
        #expect(transport.attemptCount == expectedAttempts)
    }

    @Test("A transport's cancelled, while the delivery isn't cancelled, is a send that got no response: sent again after the backoff's first wait, and delivered")
    func transportCancelledRetried() async throws {
        let endpoint = try #require(URL(string: "https://collector.example.com/batches"))
        let clock = TestClock()
        let transport = ScriptedTransport([.failure(.cancelled), .success(HTTPResponse(status: .ok))], clock: clock)
        let sut = HTTPDestination(endpoint: endpoint, transport: transport, encoder: IdentifiersEncoder(), clock: clock)
        let batch = [EventRecord(event: SignedUp(plan: "a"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)]
        let expected: [Duration] = [.zero, .seconds(1)]
        var attempts = transport.attempts.makeAsyncIterator()
        let receiving = Task { await sut.send(batch) }

        _ = await attempts.next()
        while (try? await clock.checkSuspension()) != nil {}
        await clock.advance(by: .seconds(1))
        let outcome = await receiving.value

        guard case .delivered = outcome else {
            Issue.record("Expected delivered, got \(outcome)")
            return
        }
        #expect(transport.sentAt.withLock { $0 } == expected)
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

    @Test("A clock whose sleep throws something other than CancellationError ends the retries after that attempt, without a drop report")
    func throwingClockAbandons() async throws {
        let endpoint = try #require(URL(string: "https://collector.example.com/batches"))
        let transport = ScriptedTransport([.failure(.failed(reason: "offline")), .success(HTTPResponse(status: .badRequest))], clock: TestClock())
        let sut = HTTPDestination(endpoint: endpoint, transport: transport, encoder: IdentifiersEncoder(), clock: ThrowingClock())
        let batch = [EventRecord(event: SignedUp(plan: "a"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)]
        let rejected = [EventRecord(event: SignedUp(plan: "b"), timestamp: Date(timeIntervalSince1970: 1), sourceLocation: nil)]
        let expectedAttempts = 1

        let outcome = await sut.send(batch)

        guard case .abandoned(let error) = outcome else {
            Issue.record("Expected abandoned, got \(outcome)")
            return
        }
        #expect(error is ThrowingClock.Failure)
        #expect(transport.attemptCount == expectedAttempts)
        // The next batch is answered with 400; a report of the abandoned batch would come first.
        await sut.receive(rejected)
        var reports = sut.dropReports.makeAsyncIterator()
        let actual = await reports.next()
        #expect(actual == .rejected(status: .badRequest, recordIDs: rejected.map(\.id)))
    }

    @Test("A batch the encoder can't encode is not sent, and is reported with the encoder's error and its records' identifiers")
    func notEncodedReported() async throws {
        let endpoint = try #require(URL(string: "https://collector.example.com/batches"))
        let clock = TestClock()
        let transport = ScriptedTransport([.success(HTTPResponse(status: .ok))], clock: clock)
        let sut = HTTPDestination(endpoint: endpoint, transport: transport, encoder: FailingEncoder(), clock: clock)
        let batch = [EventRecord(event: SignedUp(plan: "a"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)]
        let expected = HTTPDropReport<Unencodable>.notEncoded(Unencodable(), recordIDs: batch.map(\.id))
        let expectedAttempts = 0

        await sut.receive(batch)

        var reports = sut.dropReports.makeAsyncIterator()
        let actual = await reports.next()
        #expect(actual == expected)
        #expect(transport.attemptCount == expectedAttempts)
    }

    @Test("Reports come in the order batches are dropped, a copy of the destination reporting on the same sequence")
    func reportsInOrderAcrossCopies() async throws {
        let endpoint = try #require(URL(string: "https://collector.example.com/batches"))
        let clock = TestClock()
        let transport = ScriptedTransport([.success(HTTPResponse(status: .badRequest)), .success(HTTPResponse(status: .forbidden))], clock: clock)
        let sut = HTTPDestination(endpoint: endpoint, transport: transport, encoder: IdentifiersEncoder(), clock: clock)
        let copy = sut
        let first = [EventRecord(event: SignedUp(plan: "a"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)]
        let second = [EventRecord(event: SignedUp(plan: "b"), timestamp: Date(timeIntervalSince1970: 1), sourceLocation: nil)]
        let expected: [HTTPDropReport<Never>] = [
            .rejected(status: .badRequest, recordIDs: first.map(\.id)),
            .rejected(status: .forbidden, recordIDs: second.map(\.id)),
        ]

        await sut.receive(first)
        await copy.receive(second)

        var reports = sut.dropReports.makeAsyncIterator()
        var actual: [HTTPDropReport<Never>] = []
        for _ in expected {
            if let report = await reports.next() { actual.append(report) }
        }
        #expect(actual == expected)
    }

    @Test("The drop reports end once the destination and its copies are gone")
    func reportsEnd() async throws {
        let endpoint = try #require(URL(string: "https://collector.example.com/batches"))
        let reports = {
            let sut = HTTPDestination(endpoint: endpoint, transport: ScriptedTransport([.success(HTTPResponse(status: .ok))], clock: TestClock()), encoder: IdentifiersEncoder(), clock: TestClock())
            return sut.dropReports
        }()

        var iterator = reports.makeAsyncIterator()
        let actual = await iterator.next()

        #expect(actual == nil)
    }

    @Test("Cancelling during a wait between attempts stops the retries at once: receive returns, nothing more is sent, and nothing is reported")
    func cancelledDuringWait() async throws {
        let endpoint = try #require(URL(string: "https://collector.example.com/batches"))
        let clock = TestClock()
        let transport = ScriptedTransport([.failure(.failed(reason: "offline")), .success(HTTPResponse(status: .badRequest))], clock: clock)
        let sut = HTTPDestination(endpoint: endpoint, transport: transport, encoder: IdentifiersEncoder(), clock: clock)
        let batch = [EventRecord(event: SignedUp(plan: "a"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)]
        let rejected = [EventRecord(event: SignedUp(plan: "b"), timestamp: Date(timeIntervalSince1970: 1), sourceLocation: nil)]
        let expectedAttempts = 1
        var attempts = transport.attempts.makeAsyncIterator()
        let receiving = Task { await sut.send(batch) }
        _ = await attempts.next()
        while (try? await clock.checkSuspension()) != nil {}

        receiving.cancel()
        let outcome = await receiving.value

        guard case .cancelled = outcome else {
            Issue.record("Expected cancelled, got \(outcome)")
            return
        }
        await clock.advance(by: .seconds(60))
        #expect(transport.attemptCount == expectedAttempts)
        // The next batch is answered with 400; a report of the cancelled batch would come first.
        await sut.receive(rejected)
        var reports = sut.dropReports.makeAsyncIterator()
        let actual = await reports.next()
        #expect(actual == .rejected(status: .badRequest, recordIDs: rejected.map(\.id)))
    }

    @Test("Cancelling during a send cancels it and stops the retries: receive returns after one attempt, and nothing is reported")
    func cancelledDuringSend() async throws {
        let endpoint = try #require(URL(string: "https://collector.example.com/batches"))
        let clock = TestClock()
        let transport = GatedTransport()
        let sut = HTTPDestination(endpoint: endpoint, transport: transport, encoder: IdentifiersEncoder(), clock: clock)
        let batch = [EventRecord(event: SignedUp(plan: "a"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)]
        let expectedAttempts = 1
        let receiving = Task { await sut.send(batch) }
        try await transport.started.execute()

        receiving.cancel()
        let outcome = await receiving.value

        guard case .cancelled = outcome else {
            Issue.record("Expected cancelled, got \(outcome)")
            return
        }
        #expect(transport.sawCancellation.withLock { $0 })
        #expect(transport.attemptCount.withLock { $0 } == expectedAttempts)
        await #expect(throws: Never.self) { try await clock.checkSuspension() }
    }

    /// A clock whose every sleep returns at once, cancelled or not.
    struct UncancellableClock: Clock {
        var now: ContinuousClock.Instant { ContinuousClock().now }
        var minimumResolution: Duration { .zero }

        func sleep(until deadline: ContinuousClock.Instant, tolerance: Duration?) async throws {}
    }

    @Test("Cancelling during a send stops the retries even when the clock's sleep ignores cancellation")
    func cancelledWithUncancellableClock() async throws {
        let endpoint = try #require(URL(string: "https://collector.example.com/batches"))
        let transport = GatedTransport()
        let sut = HTTPDestination(endpoint: endpoint, transport: transport, encoder: IdentifiersEncoder(), clock: UncancellableClock())
        let batch = [EventRecord(event: SignedUp(plan: "a"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)]
        let expectedAttempts = 1
        let receiving = Task { await sut.send(batch) }
        try await transport.started.execute()

        receiving.cancel()
        let outcome = await receiving.value

        guard case .cancelled = outcome else {
            Issue.record("Expected cancelled, got \(outcome)")
            return
        }
        #expect(transport.attemptCount.withLock { $0 } == expectedAttempts)
    }

    @Test("Cancelling a delivery while its batch is retried ends the delivery with CancellationError")
    func cancellingDeliveryDuringRetry() async throws {
        let endpoint = try #require(URL(string: "https://collector.example.com/batches"))
        let clock = TestClock()
        let transport = ScriptedTransport([.failure(.failed(reason: "offline"))], clock: clock)
        let sut = HTTPDestination(endpoint: endpoint, transport: transport, encoder: IdentifiersEncoder(), clock: clock)
        let tracker = Tracker()
        let delivery = tracker.records.batch(strategy: .count(1)).deliver(to: sut)
        var attempts = transport.attempts.makeAsyncIterator()
        tracker.track(SignedUp(plan: "a"))
        let running = Task { try await delivery.execute() }
        _ = await attempts.next()
        while (try? await clock.checkSuspension()) != nil {}

        running.cancel()
        let result = await running.result

        #expect(throws: CancellationError.self) { try result.get() }
        #expect(transport.attemptCount == 1)
        await tracker.finish()
    }

    @Test("While a batch is retried, the next waits for it, and another destination receives every batch meanwhile")
    func retryHoldsOnlyThisDestination() async throws {
        let endpoint = try #require(URL(string: "https://collector.example.com/batches"))
        let clock = TestClock()
        let transport = ScriptedTransport([.failure(.failed(reason: "offline")), .success(HTTPResponse(status: .ok))], clock: clock)
        let sut = HTTPDestination(endpoint: endpoint, transport: transport, encoder: IdentifiersEncoder(), clock: clock)
        let other = InMemoryDestination()
        let tracker = Tracker()
        let delivery = tracker.records.batch(strategy: .count(1)).deliver(to: sut, other)
        var attempts = transport.attempts.makeAsyncIterator()
        var deliveries = other.deliveries.makeAsyncIterator()
        let expectedBeforeWait = 1
        let expectedPlans = ["a", "b"]
        tracker.track(SignedUp(plan: "a"))
        tracker.track(SignedUp(plan: "b"))
        let running = Task { try await delivery.execute() }

        _ = await attempts.next()
        _ = await deliveries.next()
        _ = await deliveries.next()
        while (try? await clock.checkSuspension()) != nil {}
        let actualBeforeWait = transport.attemptCount
        await clock.advance(by: .seconds(1))
        await tracker.finish()
        try await running.value

        let expectedBodies = other.records.map { Data($0.id.uuidString.utf8) }
        let actualBodies = transport.bodies.withLock { Array($0.dropFirst()) }
        #expect(actualBeforeWait == expectedBeforeWait)
        #expect(other.events(of: SignedUp.self).map(\.plan) == expectedPlans)
        #expect(actualBodies == expectedBodies)
    }
}
