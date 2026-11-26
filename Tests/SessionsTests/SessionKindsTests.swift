import Clocks
import Events
import Foundation
import Sessions
import Testing
import Trackers

@Suite("Sessions: turning session events off", .timeLimit(.minutes(1)))
struct SessionKindsTests {
    struct Tapped: Event {
        var number: Int
    }

    @Test("With no kinds, no session event is tracked, and every record still carries its session's key, rotating at the timeout")
    func noKindsKeepsTheKey() async throws {
        let clock = TestClock()
        let origin = Date(timeIntervalSinceReferenceDate: 1_000)
        let sut = Tracker(enrichers: [try .sessions(timeout: .seconds(60), kinds: [])], now: {
            let elapsed = TestClock<Duration>.Instant().duration(to: clock.now).components
            return origin.addingTimeInterval(Double(elapsed.seconds) + Double(elapsed.attoseconds) * 1e-18)
        })
        let expectedEvents = ["Tapped(number: 1)", "Tapped(number: 2)", "Tapped(number: 3)"]

        sut.track(Tapped(number: 1))
        await clock.advance(by: .seconds(59))
        sut.track(Tapped(number: 2))
        await clock.advance(by: .seconds(60))
        sut.track(Tapped(number: 3))
        await sut.finish()

        var records: [EventRecord] = []
        for await record in sut.records {
            records.append(record)
        }
        let actualEvents = records.map { String(describing: $0.event) }
        let first = try #require(records[0].context[SessionKey.self])
        let second = try #require(records[2].context[SessionKey.self])
        #expect(actualEvents == expectedEvents)
        #expect(records[1].context[SessionKey.self] == first)
        #expect(first != second)
    }

    @Test("With only starts, SessionStarted is tracked and SessionEnded isn't")
    func startsOnly() async throws {
        let clock = TestClock()
        let origin = Date(timeIntervalSinceReferenceDate: 1_000)
        let sut = Tracker(enrichers: [try .sessions(timeout: .seconds(60), kinds: [.started])], now: {
            let elapsed = TestClock<Duration>.Instant().duration(to: clock.now).components
            return origin.addingTimeInterval(Double(elapsed.seconds) + Double(elapsed.attoseconds) * 1e-18)
        })
        let expected = ["SessionStarted()", "Tapped(number: 1)", "SessionStarted()", "Tapped(number: 2)"]

        sut.track(Tapped(number: 1))
        await clock.advance(by: .seconds(60))
        sut.track(Tapped(number: 2))
        await sut.finish()

        var actual: [String] = []
        for await record in sut.records {
            actual.append(String(describing: record.event))
        }
        #expect(actual == expected)
    }

    @Test("With only ends, SessionEnded is tracked and SessionStarted isn't")
    func endsOnly() async throws {
        let clock = TestClock()
        let origin = Date(timeIntervalSinceReferenceDate: 1_000)
        let sut = Tracker(enrichers: [try .sessions(timeout: .seconds(60), kinds: [.ended])], now: {
            let elapsed = TestClock<Duration>.Instant().duration(to: clock.now).components
            return origin.addingTimeInterval(Double(elapsed.seconds) + Double(elapsed.attoseconds) * 1e-18)
        })
        let expected = ["Tapped(number: 1)", "SessionEnded(duration: 0.0 seconds)", "Tapped(number: 2)"]

        sut.track(Tapped(number: 1))
        await clock.advance(by: .seconds(60))
        sut.track(Tapped(number: 2))
        await sut.finish()

        var actual: [String] = []
        for await record in sut.records {
            actual.append(String(describing: record.event))
        }
        #expect(actual == expected)
    }
}
