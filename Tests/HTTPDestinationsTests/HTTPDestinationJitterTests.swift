import Events
import Foundation
import Generators
import HTTPDestinations
import HTTPTypes
import PropertyBased
import Sampling
import Synchronization
import Testing

@Suite("HTTPDestination: jittered waits", .timeLimit(.minutes(1)))
struct HTTPDestinationJitterTests {
    struct SignedUp: Event {
        var plan: String
    }

    /// Encodes a batch as its records' identifiers, one per line, as plain text, in one request
    /// with the deadline `deadline`, if any.
    struct IdentifiersEncoder: BatchEncoder {
        static let transientStatuses: Set<TransientStatus> = []

        var deadline: Date?

        func requests(for batch: [EventRecord]) -> BatchRequests<Never> {
            let body = EncodedBatch(body: Data(batch.map(\.id.uuidString).joined(separator: "\n").utf8), contentType: "text/plain")
            return BatchRequests(requests: [EncodedRequest(body: body, recordIDs: batch.map(\.id), deadline: deadline)], skippedRecords: [])
        }
    }

    /// Answers the nth request with the nth result of `script`, and every request past its end
    /// with its last; notes when, on `clock`, each request was sent.
    final class ScriptedTransport: HTTPTransport {
        let script: [Result<HTTPResponse, HTTPTransportError>]
        let elapsed: @Sendable () -> Duration
        let sentAt = Mutex<[Duration]>([])

        init(_ script: [Result<HTTPResponse, HTTPTransportError>], clock: some Clock<Duration>) {
            self.script = script
            let start = clock.now
            elapsed = { start.duration(to: clock.now) }
        }

        func send(_ request: HTTPRequest, body: Data) async throws(HTTPTransportError) -> HTTPResponse {
            let attempt = sentAt.withLock { sentAt in
                sentAt.append(elapsed())
                return sentAt.count
            }
            return try script[min(attempt, script.count) - 1].get()
        }
    }

    /// A clock whose sleep moves it to the sleep's deadline and returns at once, counting its
    /// sleeps.
    // Not swift-clocks' TestClock or ImmediateClock, whose Task.megaYield on every advance or
    // sleep starves under load across a property test's many cases (TRAF-143).
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

    /// A clock stopped at one instant, whose sleep notes its deadline and returns at once, so
    /// every sleep on it starts from the same instant, however the sleepers interleave.
    // Not a TestClock: two destinations sleeping on one TestClock must both be suspended before
    // it advances, and TestClock can only say that at least one is (checkSuspension).
    final class StoppedClock: Clock, Sendable {
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

        let deadlines = Mutex<[Duration]>([])

        var now: Instant { Instant(offset: .zero) }
        var minimumResolution: Duration { .zero }

        func sleep(until deadline: Instant, tolerance: Duration?) async throws {
            try Task.checkCancellation()
            deadlines.withLock { $0.append(deadline.offset) }
        }
    }

    @Test("With the default backoff's full jitter and a seeded generator, the waits are the seed's, each less than its nominal wait")
    func seededWaits() async throws {
        let endpoint = try #require(URL(string: "https://collector.example.com/batches"))
        let clock = AdvancingClock()
        // Recorded from this seed, and within a nanosecond of the reference waitsMatchReference
        // checks: each nominal wait times the top 32 bits of a draw over 2³².
        let expectedWaits: [Duration] = [
            Duration(secondsComponent: 0, attosecondsComponent: 573_731_502_750_888_464),
            Duration(secondsComponent: 0, attosecondsComponent: 567_358_920_350_670_813),
            Duration(secondsComponent: 3, attosecondsComponent: 250_037_706_457_078_455),
            Duration(secondsComponent: 7, attosecondsComponent: 149_397_207_424_044_607),
            Duration(secondsComponent: 12, attosecondsComponent: 992_564_652_115_106_581),
            Duration(secondsComponent: 25, attosecondsComponent: 241_061_471_402_645_109),
            Duration(secondsComponent: 50, attosecondsComponent: 22_770_063_951_611_516),
            Duration(secondsComponent: 49, attosecondsComponent: 733_370_132_744_312_285),
            Duration(secondsComponent: 51, attosecondsComponent: 660_757_949_575_781_820),
        ]
        let nominalWaits: [Duration] = [.seconds(1), .seconds(2), .seconds(4), .seconds(8), .seconds(16), .seconds(32), .seconds(60), .seconds(60), .seconds(60)]
        let failures = Array(repeating: Result<HTTPResponse, HTTPTransportError>.success(HTTPResponse(status: .tooManyRequests)), count: expectedWaits.count)
        let transport = ScriptedTransport(failures + [.success(HTTPResponse(status: .ok))], clock: clock)
        let sut = HTTPDestination(endpoint: endpoint, transport: transport, encoder: IdentifiersEncoder(), clock: clock, randomNumberGenerator: Xoshiro256StarStar(seed: 2026))
        let batch = [EventRecord(event: SignedUp(plan: "a"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)]

        await sut.receive(batch)

        let actual = transport.sentAt.withLock { sentAt in zip(sentAt.dropFirst(), sentAt).map { $0 - $1 } }
        #expect(actual == expectedWaits)
        #expect(zip(actual, nominalWaits).allSatisfy { $0 >= .zero && $0 < $1 })
    }

    @Test("For any backoff of whole milliseconds under 295 s with full jitter, each wait is at least zero and less than delay(beforeRetry:), and within a nanosecond of that wait times the top 32 bits of the generator's next draw over 2³², as a naive reference computes it")
    func waitsMatchReference() async throws {
        await propertyCheck(count: 100, input: Gen.uint64(in: .min ... .max)) { seed in
            var random = Xoshiro256StarStar(seed: seed)
            let initialMilliseconds = random.integer(in: 1 ... 10_000)
            let maximumMilliseconds = random.integer(in: initialMilliseconds ... 295_000)
            let retries = random.integer(in: 1 ... 10)
            let generatorSeed = random.next()
            let endpoint = try #require(URL(string: "https://collector.example.com/batches"))
            let clock = AdvancingClock()
            let backoff = try ExponentialBackoff(initialDelay: .milliseconds(initialMilliseconds), maximumDelay: .milliseconds(maximumMilliseconds), jitter: .full)
            let nominalWaits = try (1 ... retries).map { try backoff.delay(beforeRetry: $0) }
            // The reference draws from a copy of the destination's generator, one draw a wait.
            var reference = Xoshiro256StarStar(seed: generatorSeed)
            let expectedWaits = nominalWaits.map { nominal in nominal * (Double(reference.next() >> 32) / 4_294_967_296) }
            let failures = Array(repeating: Result<HTTPResponse, HTTPTransportError>.failure(.failed(reason: "offline")), count: retries)
            let transport = ScriptedTransport(failures + [.success(HTTPResponse(status: .ok))], clock: clock)
            let sut = HTTPDestination(endpoint: endpoint, transport: transport, encoder: IdentifiersEncoder(), backoff: backoff, clock: clock, randomNumberGenerator: Xoshiro256StarStar(seed: generatorSeed))
            let batch = [EventRecord(event: SignedUp(plan: "a"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)]
            let tolerance = Duration.nanoseconds(1)
            let expectedSleeps = retries

            await sut.receive(batch)

            let actual = transport.sentAt.withLock { sentAt in zip(sentAt.dropFirst(), sentAt).map { $0 - $1 } }
            let actualSleeps = clock.sleepCount.withLock { $0 }
            #expect(actual.count == retries, "seed \(seed)")
            for (wait, (nominal, expected)) in zip(actual, zip(nominalWaits, expectedWaits)) {
                let difference = wait > expected ? wait - expected : expected - wait
                #expect(wait >= .zero && wait < nominal, "seed \(seed)")
                #expect(difference <= tolerance, "seed \(seed)")
            }
            #expect(actualSleeps == expectedSleeps, "seed \(seed)")
        }
    }

    @Test("Two destinations refused by the same 429 at the same instant, each with its own seeded generator, retry at different instants, each before the nominal 1 s")
    func refusedTogetherRetryApart() async throws {
        let endpoint = try #require(URL(string: "https://collector.example.com/batches"))
        let clock = StoppedClock()
        let script: [Result<HTTPResponse, HTTPTransportError>] = [.success(HTTPResponse(status: .tooManyRequests)), .success(HTTPResponse(status: .ok))]
        let first = HTTPDestination(endpoint: endpoint, transport: ScriptedTransport(script, clock: clock), encoder: IdentifiersEncoder(), clock: clock, randomNumberGenerator: Xoshiro256StarStar(seed: 1))
        let second = HTTPDestination(endpoint: endpoint, transport: ScriptedTransport(script, clock: clock), encoder: IdentifiersEncoder(), clock: clock, randomNumberGenerator: Xoshiro256StarStar(seed: 2))
        let batch = [EventRecord(event: SignedUp(plan: "a"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)]
        let expectedRetries = 2
        let nominal = Duration.seconds(1)

        async let firstReceived: Void = first.receive(batch)
        async let secondReceived: Void = second.receive(batch)
        _ = await (firstReceived, secondReceived)

        let actual = clock.deadlines.withLock { $0 }
        try #require(actual.count == expectedRetries)
        #expect(actual[0] != actual[1])
        #expect(actual.allSatisfy { $0 >= .zero && $0 < nominal })
    }

    @Test("A destination and its copy draw in turn from the one generator they were given, so their requests' waits are its first draws, not one draw each")
    func copiesShareGenerator() async throws {
        let endpoint = try #require(URL(string: "https://collector.example.com/batches"))
        let clock = AdvancingClock()
        let offline = Result<HTTPResponse, HTTPTransportError>.failure(.failed(reason: "offline"))
        let delivered = Result<HTTPResponse, HTTPTransportError>.success(HTTPResponse(status: .ok))
        let transport = ScriptedTransport([offline, delivered, offline, delivered], clock: clock)
        let sut = HTTPDestination(endpoint: endpoint, transport: transport, encoder: IdentifiersEncoder(), clock: clock, randomNumberGenerator: Xoshiro256StarStar(seed: 7))
        let copy = sut
        let first = [EventRecord(event: SignedUp(plan: "a"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)]
        let second = [EventRecord(event: SignedUp(plan: "b"), timestamp: Date(timeIntervalSince1970: 1), sourceLocation: nil)]
        var reference = Xoshiro256StarStar(seed: 7)
        let expectedWaits = [reference.next(), reference.next()].map { Duration.seconds(1) * (Double($0 >> 32) / 4_294_967_296) }
        let tolerance = Duration.nanoseconds(1)

        await sut.receive(first)
        await copy.receive(second)

        let sentAt = transport.sentAt.withLock { $0 }
        try #require(sentAt.count == 4)
        let actual = [sentAt[1] - sentAt[0], sentAt[3] - sentAt[2]]
        for (wait, expected) in zip(actual, expectedWaits) {
            let difference = wait > expected ? wait - expected : expected - wait
            #expect(difference <= tolerance)
        }
        #expect(actual[0] != actual[1])
    }

    @Test("A jittered wait is checked against the request's deadline as any wait is: a request refused at its deadline is dropped once the wait has passed it, and not sent again")
    func jitteredWaitPastDeadline() async throws {
        let endpoint = try #require(URL(string: "https://collector.example.com/batches"))
        let clock = AdvancingClock()
        let start = Date(timeIntervalSince1970: 1_000_000)
        let deadline = start
        let transport = ScriptedTransport([.success(HTTPResponse(status: .serviceUnavailable)), .success(HTTPResponse(status: .ok))], clock: clock)
        // The wall clock reads the deadline until the clock has slept, then past it.
        let wallClock: @Sendable () -> Date = {
            let offset = clock.now.offset
            return start.addingTimeInterval(Double(offset.components.seconds) + Double(offset.components.attoseconds) * 1e-18)
        }
        let sut = HTTPDestination(endpoint: endpoint, transport: transport, encoder: IdentifiersEncoder(deadline: deadline), clock: clock, randomNumberGenerator: Xoshiro256StarStar(seed: 2026), now: wallClock)
        let batch = [EventRecord(event: SignedUp(plan: "a"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)]
        let expectedSentAt: [Duration] = [.zero]
        let expectedSleeps = 1
        let expected = HTTPDropReport<Never>.deadlineExceeded(deadline: deadline, recordIDs: batch.map(\.id))

        await sut.receive(batch)

        var reports = sut.dropReports.makeAsyncIterator()
        let actual = await reports.next()
        #expect(transport.sentAt.withLock { $0 } == expectedSentAt)
        #expect(clock.sleepCount.withLock { $0 } == expectedSleeps)
        #expect(clock.now.offset > .zero)
        #expect(actual == expected)
    }
}
