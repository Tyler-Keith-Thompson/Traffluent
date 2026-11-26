import Events
import Foundation
import Sessions
import Synchronization
import Testing
import Trackers

@Suite("Sessions: sampling whole sessions", .timeLimit(.minutes(1)))
struct SessionSamplingTests {
    struct Tapped: Event {
        var number: Int
    }

    /// Hands out the times of `sessions` sessions of three events each: one second apart within a
    /// session, two minutes between sessions, around a 60 second timeout.
    final class Stamps: Sendable {
        private let index = Atomic(0)

        func next() -> Date {
            let number = index.add(1, ordering: .relaxed).oldValue
            return Date(timeIntervalSinceReferenceDate: Double(number / 3 * 120 + number % 3))
        }
    }

    // Session IDs are random UUIDs that a test can't inject (D4), so which sessions are kept differs
    // between runs even with the seed fixed; the test pins only what holds for any outcome.
    @Test("Each session is kept or dropped whole, its start and end with it, and its kept records carry the rate")
    func wholeSessions() async throws {
        let sessions = 40
        let stamps = Stamps()
        let sut = Tracker(enrichers: [try .sessions(timeout: .seconds(60))], samplers: [.sessions(rate: try SampleRate(0.5))], samplingSeed: 7, now: stamps.next)
        let expectedRate: SampleRate = try SampleRate(0.5)

        for number in 0 ..< sessions * 3 {
            sut.track(Tapped(number: number))
        }
        await sut.finish()

        var byID: [UUID: [String]] = [:]
        var rates: [SampleRate?] = []
        var kept = 0
        for await record in sut.records {
            let id = try #require(record.context[SessionKey.self])
            byID[id, default: []].append("\(record.event)")
            rates.append(record.context[SampleRateKey.self])
            kept += 1
        }
        var dropped = 0
        for await report in sut.samplingDropReports {
            dropped += report.recordCount
        }
        // Every session kept is complete: its start, its three taps, numbered in one session's
        // run, and its end unless it is the last session.
        for events in byID.values {
            let numbers = events.compactMap { event in
                event.hasPrefix("Tapped(number: ") ? Int(event.dropFirst(15).dropLast()) : nil
            }
            let session = try #require(numbers.first.map { $0 / 3 })
            let expectedNumbers = [session * 3, session * 3 + 1, session * 3 + 2]
            let expectedEnds = session == sessions - 1 ? 0 : 1
            #expect(numbers == expectedNumbers)
            #expect(events.first == "SessionStarted()")
            #expect(events.filter { $0.hasPrefix("SessionEnded") }.count == expectedEnds)
        }
        // Both outcomes happen: all 40 sessions deciding alike has probability 2^-39.
        #expect(!byID.isEmpty)
        #expect(byID.count < sessions)
        #expect(rates.allSatisfy { $0 == expectedRate })
        // Every session's records: 3 taps and a start each, and an end for all but the last.
        #expect(kept + dropped == sessions * 4 + sessions - 1)
    }

    @Test("Sampling sessions at 0 keeps none of their records; at 1, every one, carrying rate 1", arguments: [0.0, 1.0])
    func boundaries(rate: Double) async throws {
        let sut = Tracker(enrichers: [try .sessions(timeout: .seconds(60))], samplers: [.sessions(rate: try SampleRate(rate))], samplingSeed: 1, now: Stamps().next)
        let expected = rate == 0 ? 0 : 6 * 4 + 5
        let expectedRates = rate == 0 ? [] : Array(repeating: try SampleRate(1), count: expected)

        for number in 0 ..< 18 {
            sut.track(Tapped(number: number))
        }
        await sut.finish()

        var actual: [SampleRate?] = []
        for await record in sut.records {
            actual.append(record.context[SampleRateKey.self])
        }
        #expect(actual.count == expected)
        #expect(actual == expectedRates)
    }

    @Test("A session sampler given a predicate drops only the records it selects, and keeps the session's others")
    func predicate() async throws {
        let sut = Tracker(enrichers: [.sessions()], samplers: [.sessions(where: { $0.event is Tapped }, rate: try SampleRate(0))], samplingSeed: 1)
        let expected = ["SessionStarted()"]

        sut.track(Tapped(number: 0))
        sut.track(Tapped(number: 1))
        await sut.finish()

        var actual: [String] = []
        for await record in sut.records {
            actual.append("\(record.event)")
        }
        #expect(actual == expected)
    }

    @Test("A record with no session, the sessions enricher left out, is kept, with no rate")
    func noSession() async throws {
        let sut = Tracker(samplers: [.sessions(rate: try SampleRate(0))], samplingSeed: 1)
        let expected: [SampleRate?] = [nil]

        sut.track(Tapped(number: 0))
        await sut.finish()

        var actual: [SampleRate?] = []
        for await record in sut.records {
            actual.append(record.context[SampleRateKey.self])
        }
        #expect(actual == expected)
    }
}
