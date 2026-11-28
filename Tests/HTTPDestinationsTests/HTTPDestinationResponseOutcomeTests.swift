import Clocks
import Events
import Foundation
import Generators
import HTTPDestinations
import HTTPTypes
import PropertyBased
import Sampling
import Synchronization
import Testing

@Suite("HTTPDestination: what a 2xx answer's body says", .timeLimit(.minutes(1)))
struct HTTPDestinationResponseOutcomeTests {
    struct SignedUp: Event {
        var plan: String
    }

    /// Encodes a batch as its records' identifiers, one per line, and counts every 2xx answer as
    /// delivered, as most vendors' encoders do.
    struct DeliveringEncoder: BatchEncoder {
        static let transientStatuses: Set<TransientStatus> = []

        static func outcome(of response: HTTPTransportResponse, for request: EncodedRequest) -> ResponseOutcome {
            .delivered
        }

        func requests(for batch: [EventRecord]) -> BatchRequests<Never> {
            let body = EncodedBatch(body: Data(batch.map(\.id.uuidString).joined(separator: "\n").utf8), contentType: "text/plain")
            return BatchRequests(requests: [EncodedRequest(body: body, recordIDs: batch.map(\.id))], skippedRecords: [])
        }
    }

    /// Encodes a batch as ``DeliveringEncoder`` does, each request with the deadline `deadline`,
    /// and reads a 2xx body of `refused:<reason>` as rejected, `busy:<reason>` as transient and
    /// any other as delivered.
    struct BodyReadingEncoder: BatchEncoder {
        static let transientStatuses: Set<TransientStatus> = []

        static func outcome(of response: HTTPTransportResponse, for request: EncodedRequest) -> ResponseOutcome {
            let text = String(decoding: response.body, as: UTF8.self)
            if text.hasPrefix("refused:") {
                return .rejected(reason: String(text.dropFirst("refused:".count)))
            }
            if text.hasPrefix("busy:") {
                return .transient(reason: String(text.dropFirst("busy:".count)))
            }
            return .delivered
        }

        var deadline: Date?

        func requests(for batch: [EventRecord]) -> BatchRequests<Never> {
            let body = EncodedBatch(body: Data(batch.map(\.id.uuidString).joined(separator: "\n").utf8), contentType: "text/plain")
            return BatchRequests(requests: [EncodedRequest(body: body, recordIDs: batch.map(\.id), deadline: deadline)], skippedRecords: [])
        }
    }

    /// Answers the nth request with the nth answer of `script`, and every request past its end
    /// with its last; keeps each body, calls `onSend` for each, and announces each on `attempts`.
    final class ScriptedTransport: HTTPTransport {
        let script: [Result<HTTPTransportResponse, HTTPTransportError>]
        let onSend: @Sendable () -> Void
        let bodies = Mutex<[Data]>([])
        let (attempts, attempted) = AsyncStream.makeStream(of: Int.self)

        init(_ script: [Result<HTTPTransportResponse, HTTPTransportError>], onSend: @escaping @Sendable () -> Void = {}) {
            self.script = script
            self.onSend = onSend
        }

        var attemptCount: Int {
            bodies.withLock { $0.count }
        }

        func send(_ request: HTTPRequest, body: Data) async throws(HTTPTransportError) -> HTTPTransportResponse {
            let attempt = bodies.withLock { bodies in
                bodies.append(body)
                return bodies.count
            }
            onSend()
            attempted.yield(attempt)
            return try script[min(attempt, script.count) - 1].get()
        }
    }

    /// A clock whose sleep moves it to the sleep's deadline and returns at once.
    // Not swift-clocks' ImmediateClock, whose every sleep starts background tasks that starve
    // under load (TRAF-143).
    final class AdvancingClock: Clock, Sendable {
        struct Instant: InstantProtocol {
            var offset: Duration

            func advanced(by duration: Duration) -> Instant {
                Instant(offset: offset + duration)
            }

            func duration(to other: Instant) -> Duration {
                other.offset - offset
            }

            static func < (lhs: Instant, rhs: Instant) -> Bool {
                lhs.offset < rhs.offset
            }
        }

        let current = Mutex(Instant(offset: .zero))
        let sleepCount = Mutex(0)

        var now: Instant { current.withLock { $0 } }
        var minimumResolution: Duration { .zero }

        func sleep(until deadline: Instant, tolerance: Duration?) async throws {
            try Task.checkCancellation()
            sleepCount.withLock { $0 += 1 }
            current.withLock { $0 = max($0, deadline) }
        }
    }

    @Test("An encoder that counts every 2xx as delivered keeps a 2xx delivered whatever its body says, sends it once and reports nothing")
    func deliveringEncoderKeepsSuccess() async throws {
        let endpoint = try #require(URL(string: "https://collector.example.com/batches"))
        let refusingBody = Data(#"{"status":0,"error":"refused"}"#.utf8)
        let transport = ScriptedTransport([
            .success(HTTPTransportResponse(head: HTTPResponse(status: .ok), body: refusingBody)),
            .success(HTTPTransportResponse(head: HTTPResponse(status: .badRequest), body: Data())),
        ])
        let sut = HTTPDestination(endpoint: endpoint, transport: transport, encoder: DeliveringEncoder())
        let batch = [EventRecord(event: SignedUp(plan: "a"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)]
        let rejected = [EventRecord(event: SignedUp(plan: "b"), timestamp: Date(timeIntervalSince1970: 1), sourceLocation: nil)]
        let expectedAttempts = 1
        let expected = HTTPDropReport<Never>.rejected(status: .badRequest, recordIDs: rejected.map(\.id))

        await sut.receive(batch)

        #expect(transport.attemptCount == expectedAttempts)
        // The next batch is answered with 400; a report of the first would come before its own.
        await sut.receive(rejected)
        var reports = sut.dropReports.makeAsyncIterator()
        let actual = await reports.next()
        #expect(actual == expected)
    }

    @Test("A 2xx the encoder reads as rejected is sent once, then dropped and reported with its status, the encoder's reason and its records", arguments: [200, 202, 204, 299])
    func rejectedInBodyReported(code: Int) async throws {
        let endpoint = try #require(URL(string: "https://collector.example.com/batches"))
        let status = HTTPResponse.Status(code: code)
        let transport = ScriptedTransport([
            .success(HTTPTransportResponse(head: HTTPResponse(status: status), body: Data("refused:unknown token".utf8))),
            .success(HTTPTransportResponse(head: HTTPResponse(status: .badRequest), body: Data())),
        ])
        let sut = HTTPDestination(endpoint: endpoint, transport: transport, encoder: BodyReadingEncoder())
        let batch = [
            EventRecord(event: SignedUp(plan: "a"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil),
            EventRecord(event: SignedUp(plan: "b"), timestamp: Date(timeIntervalSince1970: 1), sourceLocation: nil),
        ]
        let rejected = [EventRecord(event: SignedUp(plan: "c"), timestamp: Date(timeIntervalSince1970: 2), sourceLocation: nil)]
        let expectedAttempts = 2
        let expected = HTTPDropReport<Never>.rejectedInBody(status: status, reason: "unknown token", recordIDs: batch.map(\.id))

        await sut.receive(batch)
        // Answered with 400, so its report comes next, and a missing report of the first batch
        // fails rather than waits.
        await sut.receive(rejected)

        var reports = sut.dropReports.makeAsyncIterator()
        let actual = await reports.next()
        #expect(actual == expected)
        #expect(transport.attemptCount == expectedAttempts)
    }

    @Test("A 3xx's body isn't read: it is rejected by its status, as no 2xx answered it", arguments: [300, 302])
    func redirectNotRead(code: Int) async throws {
        let endpoint = try #require(URL(string: "https://collector.example.com/batches"))
        let status = HTTPResponse.Status(code: code)
        let transport = ScriptedTransport([
            .success(HTTPTransportResponse(head: HTTPResponse(status: status), body: Data("refused:unknown token".utf8))),
            .success(HTTPTransportResponse(head: HTTPResponse(status: .badRequest), body: Data())),
        ])
        let sut = HTTPDestination(endpoint: endpoint, transport: transport, encoder: BodyReadingEncoder())
        let batch = [EventRecord(event: SignedUp(plan: "a"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)]
        let rejected = [EventRecord(event: SignedUp(plan: "b"), timestamp: Date(timeIntervalSince1970: 1), sourceLocation: nil)]
        let expected = HTTPDropReport<Never>.rejected(status: status, recordIDs: batch.map(\.id))

        await sut.receive(batch)
        // Answered with 400, so its report comes next, and a missing report of the first batch
        // fails rather than waits.
        await sut.receive(rejected)

        var reports = sut.dropReports.makeAsyncIterator()
        let actual = await reports.next()
        #expect(actual == expected)
    }

    @Test("A failure status's body isn't read: a 400 saying refused is rejected by its status, and a 503 saying refused is retried")
    func failureBodiesNotRead() async throws {
        let endpoint = try #require(URL(string: "https://collector.example.com/batches"))
        let refusing = Data("refused:unknown token".utf8)
        let clock = AdvancingClock()
        let transport = ScriptedTransport([
            .success(HTTPTransportResponse(head: HTTPResponse(status: .badRequest), body: refusing)),
            .success(HTTPTransportResponse(head: HTTPResponse(status: .serviceUnavailable), body: refusing)),
            .success(HTTPTransportResponse(head: HTTPResponse(status: .ok), body: Data())),
            .success(HTTPTransportResponse(head: HTTPResponse(status: .badRequest), body: Data())),
        ])
        let sut = HTTPDestination(endpoint: endpoint, transport: transport, encoder: BodyReadingEncoder(), clock: clock)
        let rejected = [EventRecord(event: SignedUp(plan: "a"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)]
        let retried = [EventRecord(event: SignedUp(plan: "b"), timestamp: Date(timeIntervalSince1970: 1), sourceLocation: nil)]
        let last = [EventRecord(event: SignedUp(plan: "c"), timestamp: Date(timeIntervalSince1970: 2), sourceLocation: nil)]
        let expectedAttempts = 4
        let expected: [HTTPDropReport<Never>] = [
            .rejected(status: .badRequest, recordIDs: rejected.map(\.id)),
            .rejected(status: .badRequest, recordIDs: last.map(\.id)),
        ]

        await sut.receive(rejected)
        await sut.receive(retried)
        // Answered with 400: the retried batch was delivered, so this report follows the first.
        await sut.receive(last)

        var reports = sut.dropReports.makeAsyncIterator()
        var actual: [HTTPDropReport<Never>] = []
        for _ in expected {
            actual.append(await reports.next() ?? .rejected(status: .ok, recordIDs: []))
        }
        #expect(actual == expected)
        #expect(transport.attemptCount == expectedAttempts)
    }

    @Test("A 2xx the encoder reads as transient is sent again after the backoff's wait, byte for byte, until a 2xx it reads as delivered, and nothing is reported")
    func transientInBodyRetried() async throws {
        let endpoint = try #require(URL(string: "https://collector.example.com/batches"))
        let clock = TestClock()
        let transport = ScriptedTransport([
            .success(HTTPTransportResponse(head: HTTPResponse(status: .ok), body: Data("busy:queue full".utf8))),
            .success(HTTPTransportResponse(head: HTTPResponse(status: .ok), body: Data())),
            .success(HTTPTransportResponse(head: HTTPResponse(status: .badRequest), body: Data())),
        ])
        let sut = HTTPDestination(endpoint: endpoint, transport: transport, encoder: BodyReadingEncoder(), backoff: ExponentialBackoff(jitter: .none), clock: clock)
        let batch = [EventRecord(event: SignedUp(plan: "a"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)]
        let rejected = [EventRecord(event: SignedUp(plan: "b"), timestamp: Date(timeIntervalSince1970: 1), sourceLocation: nil)]
        let expectedBodies = Array(repeating: Data(batch[0].id.uuidString.utf8), count: 2)
        let expected = HTTPDropReport<Never>.rejected(status: .badRequest, recordIDs: rejected.map(\.id))
        var attempts = transport.attempts.makeAsyncIterator()
        let receiving = Task { await sut.receive(batch) }

        _ = await attempts.next()
        while (try? await clock.checkSuspension()) != nil {}
        // Short of the first wait, so a retry sent without one fails here.
        await clock.advance(by: .milliseconds(999))
        let attemptsBeforeWait = transport.attemptCount
        await clock.advance(by: .milliseconds(1))
        await receiving.value

        #expect(attemptsBeforeWait == 1)
        // Required, as the next batch's answer is the script's third only after two attempts.
        try #require(transport.bodies.withLock { $0 } == expectedBodies)
        // The next batch is answered with 400; a report of the retried batch would come first.
        await sut.receive(rejected)
        var reports = sut.dropReports.makeAsyncIterator()
        let actual = await reports.next()
        #expect(actual == expected)
    }

    @Test("A 2xx the encoder reads as transient once its request's deadline has passed is reported as past the deadline at once, not sent again")
    func transientInBodyPastDeadline() async throws {
        let endpoint = try #require(URL(string: "https://collector.example.com/batches"))
        let deadline = Date(timeIntervalSince1970: 1_000)
        // The wall clock reads the deadline itself before the first attempt, and a millisecond
        // past it once the answer has come.
        let wallClock = Mutex(deadline)
        let transport = ScriptedTransport([.success(HTTPTransportResponse(head: HTTPResponse(status: .ok), body: Data("busy:queue full".utf8)))]) {
            wallClock.withLock { $0 = deadline.addingTimeInterval(0.001) }
        }
        let clock = AdvancingClock()
        let sut = HTTPDestination(endpoint: endpoint, transport: transport, encoder: BodyReadingEncoder(deadline: deadline), clock: clock, now: { wallClock.withLock { $0 } })
        let batch = [EventRecord(event: SignedUp(plan: "a"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)]
        let later = [EventRecord(event: SignedUp(plan: "b"), timestamp: Date(timeIntervalSince1970: 1), sourceLocation: nil)]
        let expectedAttempts = 1
        let expectedSleeps = 0
        let expected = HTTPDropReport<Never>.deadlineExceeded(deadline: deadline, recordIDs: batch.map(\.id))

        await sut.receive(batch)
        // Past the same deadline before it is sent, so its report comes next, and a missing
        // report of the first batch fails rather than waits.
        await sut.receive(later)

        var reports = sut.dropReports.makeAsyncIterator()
        let actual = await reports.next()
        #expect(actual == expected)
        #expect(transport.attemptCount == expectedAttempts)
        // A retry that waited before finding the deadline passed would end the same way.
        #expect(clock.sleepCount.withLock { $0 } == expectedSleeps)
    }

    /// Encodes each record as a request of its own, its body the record's identifier, and reads
    /// a 2xx body as ``BodyReadingEncoder`` does.
    struct PerRecordEncoder: BatchEncoder {
        static let transientStatuses: Set<TransientStatus> = []

        static func outcome(of response: HTTPTransportResponse, for request: EncodedRequest) -> ResponseOutcome {
            BodyReadingEncoder.outcome(of: response, for: request)
        }

        func requests(for batch: [EventRecord]) -> BatchRequests<Never> {
            let requests = batch.map { record in
                EncodedRequest(body: EncodedBatch(body: Data(record.id.uuidString.utf8), contentType: "text/plain"), recordIDs: [record.id])
            }
            return BatchRequests(requests: requests, skippedRecords: [])
        }
    }

    @Test("A 2xx read as rejected for one of a batch's requests is reported with that request's records alone, the requests after it are still sent, and the batch is done")
    func rejectedInBodyPerRequest() async throws {
        let endpoint = try #require(URL(string: "https://collector.example.com/batches"))
        let transport = ScriptedTransport([
            .success(HTTPTransportResponse(head: HTTPResponse(status: .ok), body: Data("refused:unknown token".utf8))),
            .success(HTTPTransportResponse(head: HTTPResponse(status: .ok), body: Data())),
            .success(HTTPTransportResponse(head: HTTPResponse(status: .badRequest), body: Data())),
        ])
        let sut = HTTPDestination(endpoint: endpoint, transport: transport, encoder: PerRecordEncoder())
        let batch = ["a", "b"].map { EventRecord(event: SignedUp(plan: $0), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil) }
        let rejected = [EventRecord(event: SignedUp(plan: "c"), timestamp: Date(timeIntervalSince1970: 1), sourceLocation: nil)]
        let expectedBodies = batch.map { Data($0.id.uuidString.utf8) }
        let expected = HTTPDropReport<Never>.rejectedInBody(status: .ok, reason: "unknown token", recordIDs: [batch[0].id])

        // `receive` returning is what acknowledges a batch to its delivery, which then lets the
        // store forget it.
        await sut.receive(batch)
        let actualBodies = transport.bodies.withLock { $0 }
        // Required, as the next batch's answer is the script's third only after two requests.
        try #require(actualBodies == expectedBodies)
        // Answered with 400: a report of the first batch's second request would come before it.
        await sut.receive(rejected)

        var reports = sut.dropReports.makeAsyncIterator()
        let actual = await reports.next()
        #expect(actual == expected)
    }

    /// One answer a property case scripts, and what the destination makes of it.
    enum Answer: CaseIterable {
        case delivered, refused, busy, unavailable, rejected, unanswered

        var result: Result<HTTPTransportResponse, HTTPTransportError> {
            switch self {
            case .delivered: .success(HTTPTransportResponse(head: HTTPResponse(status: .ok), body: Data()))
            case .refused: .success(HTTPTransportResponse(head: HTTPResponse(status: .accepted), body: Data("refused:no".utf8)))
            case .busy: .success(HTTPTransportResponse(head: HTTPResponse(status: .ok), body: Data("busy:later".utf8)))
            case .unavailable: .success(HTTPTransportResponse(head: HTTPResponse(status: .serviceUnavailable), body: Data("refused:no".utf8)))
            case .rejected: .success(HTTPTransportResponse(head: HTTPResponse(status: .unauthorized), body: Data("refused:no".utf8)))
            case .unanswered: .failure(.failed(reason: "offline"))
            }
        }
    }

    @Test("Against a model that stops at the first delivered, refused or rejected answer and retries the rest, the destination sends as many requests and reports the same")
    func matchesModel() async {
        await propertyCheck(count: 100, input: Gen.uint64(in: .min ... .max)) { seed in
            var random = Xoshiro256StarStar(seed: seed)
            let answers = Answer.allCases
            let drawn = (0 ..< random.integer(in: 1 ... 8)).map { _ in answers[random.integer(in: 0 ... answers.count - 1)] } + [.delivered]
            let batch = [EventRecord(event: SignedUp(plan: "a"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)]
            let ending = [EventRecord(event: SignedUp(plan: "end"), timestamp: Date(timeIntervalSince1970: 1), sourceLocation: nil)]
            // The model: every answer up to the first that ends the request is one attempt, and
            // only a refused or rejected one is reported.
            let stop = drawn.firstIndex { [.delivered, .refused, .rejected].contains($0) } ?? drawn.count - 1
            let expectedAttempts = stop + 1
            let endingReport = HTTPDropReport<Never>.rejected(status: .unauthorized, recordIDs: ending.map(\.id))
            let expectedReports: [HTTPDropReport<Never>] = switch drawn[stop] {
            case .refused: [.rejectedInBody(status: .accepted, reason: "no", recordIDs: batch.map(\.id)), endingReport]
            case .rejected: [.rejected(status: .unauthorized, recordIDs: batch.map(\.id)), endingReport]
            case .delivered, .busy, .unavailable, .unanswered: [endingReport]
            }
            // The answers the model reads, then a 401 for the ending batch, whose report comes
            // after any of the first batch's.
            let endpoint = try #require(URL(string: "https://collector.example.com/batches"))
            let transport = ScriptedTransport((drawn[...stop] + [.rejected]).map(\.result))
            let sut = HTTPDestination(endpoint: endpoint, transport: transport, encoder: BodyReadingEncoder(), backoff: try ExponentialBackoff(initialDelay: .nanoseconds(1), maximumDelay: .nanoseconds(1), jitter: .none), clock: AdvancingClock())

            await sut.receive(batch)
            let actualAttempts = transport.attemptCount
            await sut.receive(ending)

            #expect(actualAttempts == expectedAttempts, "seed \(seed)")
            // The ending batch is answered with 401 only after as many attempts as the model's.
            guard actualAttempts == expectedAttempts else {
                return
            }
            var reports = sut.dropReports.makeAsyncIterator()
            // Up to the ending batch's report, which always comes, so a missing report of the
            // first batch fails rather than waits.
            var actualReports: [HTTPDropReport<Never>] = []
            while let report = await reports.next() {
                actualReports.append(report)
                if report == endingReport {
                    break
                }
            }
            #expect(actualReports == expectedReports, "seed \(seed)")
        }
    }

    /// Encodes a batch as ``DeliveringEncoder`` does, counts every 2xx as delivered, and keeps
    /// each answer it takes note of, with the records of the request it answers, in `noted`,
    /// which its copies share.
    struct NotingEncoder: BatchEncoder {
        static let transientStatuses: Set<TransientStatus> = []

        static func outcome(of response: HTTPTransportResponse, for request: EncodedRequest) -> ResponseOutcome {
            .delivered
        }

        final class Noted: Sendable {
            let answers = Mutex<[(body: Data, recordIDs: [UUID])]>([])
        }

        let noted = Noted()

        func didReceive(_ response: HTTPTransportResponse, for request: EncodedRequest) {
            noted.answers.withLock { $0.append((body: response.body, recordIDs: request.recordIDs)) }
        }

        func requests(for batch: [EventRecord]) -> BatchRequests<Never> {
            let body = EncodedBatch(body: Data(batch.map(\.id.uuidString).joined(separator: "\n").utf8), contentType: "text/plain")
            return BatchRequests(requests: [EncodedRequest(body: body, recordIDs: batch.map(\.id))], skippedRecords: [])
        }
    }

    @Test("The destination's encoder takes note of each 2xx answer, with the request it answers, and of no 5xx it retries or 4xx it drops")
    func encoderNotesEachSuccess() async throws {
        let endpoint = try #require(URL(string: "https://collector.example.com/batches"))
        let transport = ScriptedTransport([
            .success(HTTPTransportResponse(head: HTTPResponse(status: .serviceUnavailable), body: Data("busy".utf8))),
            .success(HTTPTransportResponse(head: HTTPResponse(status: .ok), body: Data("first".utf8))),
            .success(HTTPTransportResponse(head: HTTPResponse(status: .accepted), body: Data("second".utf8))),
            .success(HTTPTransportResponse(head: HTTPResponse(status: .badRequest), body: Data("refused".utf8))),
        ])
        let encoder = NotingEncoder()
        let sut = HTTPDestination(endpoint: endpoint, transport: transport, encoder: encoder, backoff: try ExponentialBackoff(initialDelay: .nanoseconds(1), maximumDelay: .nanoseconds(1), jitter: .none), clock: AdvancingClock())
        let first = [EventRecord(event: SignedUp(plan: "a"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)]
        let second = [EventRecord(event: SignedUp(plan: "b"), timestamp: Date(timeIntervalSince1970: 1), sourceLocation: nil)]
        let refused = [EventRecord(event: SignedUp(plan: "c"), timestamp: Date(timeIntervalSince1970: 2), sourceLocation: nil)]
        let expectedBodies = [Data("first".utf8), Data("second".utf8)]
        let expectedRecordIDs = [first.map(\.id), second.map(\.id)]

        await sut.receive(first)
        await sut.receive(second)
        await sut.receive(refused)

        let actual = encoder.noted.answers.withLock { $0 }
        #expect(actual.map(\.body) == expectedBodies)
        #expect(actual.map(\.recordIDs) == expectedRecordIDs)
    }
}
