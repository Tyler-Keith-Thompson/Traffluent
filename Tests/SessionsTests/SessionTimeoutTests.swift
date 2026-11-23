import Clocks
import Events
import Foundation
import Instrumentation
import LifecycleTracking
import Sessions
import Testing
import Trackers

@Suite("Sessions: the timeout", .timeLimit(.minutes(1)))
struct SessionTimeoutTests {
    struct Tapped: Event {
        var number: Int
    }

    @Test("The first event starts the first session: SessionStarted comes before it, at its time, with its key")
    func firstEventStarts() async throws {
        let clock = TestClock()
        let origin = Date(timeIntervalSinceReferenceDate: 1_000)
        let sut = Tracker(enrichers: [.sessions()], now: {
            let elapsed = TestClock<Duration>.Instant().duration(to: clock.now).components
            return origin.addingTimeInterval(Double(elapsed.seconds) + Double(elapsed.attoseconds) * 1e-18)
        })
        let expectedEvents = ["SessionStarted()", "Tapped(number: 1)"]
        let expectedTimestamps = [origin, origin]

        sut.track(Tapped(number: 1))
        await sut.finish()

        var records: [EventRecord] = []
        for await record in sut.records {
            records.append(record)
        }
        let actualEvents = records.map { String(describing: $0.event) }
        let actualTimestamps = records.map(\.timestamp)
        #expect(actualEvents == expectedEvents)
        #expect(actualTimestamps == expectedTimestamps)
        let key = try #require(records.first?.context[SessionKey.self])
        #expect(records.allSatisfy { $0.context[SessionKey.self] == key })
    }

    @Test("Events less than the timeout apart share a session, however long it runs")
    func withinTimeout() async {
        let clock = TestClock()
        let origin = Date(timeIntervalSinceReferenceDate: 1_000)
        let timeout = Duration.seconds(60)
        let sut = Tracker(enrichers: [.sessions(timeout: timeout)], now: {
            let elapsed = TestClock<Duration>.Instant().duration(to: clock.now).components
            return origin.addingTimeInterval(Double(elapsed.seconds) + Double(elapsed.attoseconds) * 1e-18)
        })
        let expectedEvents = ["SessionStarted()", "Tapped(number: 1)", "Tapped(number: 2)", "Tapped(number: 3)"]

        sut.track(Tapped(number: 1))
        await clock.advance(by: timeout - .milliseconds(1))
        sut.track(Tapped(number: 2))
        await clock.advance(by: timeout - .milliseconds(1))
        sut.track(Tapped(number: 3))
        await sut.finish()

        var records: [EventRecord] = []
        for await record in sut.records {
            records.append(record)
        }
        let actualEvents = records.map { String(describing: $0.event) }
        let actualKeys = Set(records.map { $0.context[SessionKey.self] })
        #expect(actualEvents == expectedEvents)
        #expect(actualKeys.count == 1)
        #expect(!actualKeys.contains(nil))
    }

    @Test("An event the timeout after the one before it starts a new session: SessionEnded, then SessionStarted, come before it")
    func atTimeout() async throws {
        let clock = TestClock()
        let origin = Date(timeIntervalSinceReferenceDate: 1_000)
        let timeout = Duration.seconds(60)
        let sut = Tracker(enrichers: [.sessions(timeout: timeout)], now: {
            let elapsed = TestClock<Duration>.Instant().duration(to: clock.now).components
            return origin.addingTimeInterval(Double(elapsed.seconds) + Double(elapsed.attoseconds) * 1e-18)
        })
        let expectedEvents = [
            "SessionStarted()",
            "Tapped(number: 1)",
            "Tapped(number: 2)",
            "SessionEnded(duration: 10.0 seconds)",
            "SessionStarted()",
            "Tapped(number: 3)",
        ]
        let expectedTimestamps = [
            origin,
            origin,
            origin.addingTimeInterval(10),
            origin.addingTimeInterval(10),
            origin.addingTimeInterval(70),
            origin.addingTimeInterval(70),
        ]

        sut.track(Tapped(number: 1))
        await clock.advance(by: .seconds(10))
        sut.track(Tapped(number: 2))
        await clock.advance(by: timeout)
        sut.track(Tapped(number: 3))
        await sut.finish()

        var records: [EventRecord] = []
        for await record in sut.records {
            records.append(record)
        }
        let actualEvents = records.map { String(describing: $0.event) }
        let actualTimestamps = records.map(\.timestamp)
        let actualKeys = records.map { $0.context[SessionKey.self] }
        #expect(actualEvents == expectedEvents)
        #expect(actualTimestamps == expectedTimestamps)
        let first = try #require(actualKeys[0])
        let second = try #require(actualKeys[4])
        #expect(first != second)
        #expect(actualKeys == [first, first, first, first, second, second])
    }

    @Test("The default timeout is 30 minutes: an event 30 minutes less a second after the last stays, one 30 minutes after starts anew")
    func defaultTimeout() async {
        let clock = TestClock()
        let origin = Date(timeIntervalSinceReferenceDate: 1_000)
        let sut = Tracker(enrichers: [.sessions(kinds: [])], now: {
            let elapsed = TestClock<Duration>.Instant().duration(to: clock.now).components
            return origin.addingTimeInterval(Double(elapsed.seconds) + Double(elapsed.attoseconds) * 1e-18)
        })
        let expected = 2

        sut.track(Tapped(number: 1))
        await clock.advance(by: .seconds(30 * 60 - 1))
        sut.track(Tapped(number: 2))
        await clock.advance(by: .seconds(30 * 60))
        sut.track(Tapped(number: 3))
        await sut.finish()

        var keys: [UUID?] = []
        for await record in sut.records {
            keys.append(record.context[SessionKey.self])
        }
        let actual = Set(keys.compactMap { $0 }).count
        #expect(actual == expected)
        #expect(keys[0] == keys[1])
        #expect(keys[1] != keys[2])
    }

    @Test("Inactivity counts from the session's last event, not its first")
    func fromLastEvent() async {
        let clock = TestClock()
        let origin = Date(timeIntervalSinceReferenceDate: 1_000)
        let timeout = Duration.seconds(60)
        let sut = Tracker(enrichers: [.sessions(timeout: timeout, kinds: [])], now: {
            let elapsed = TestClock<Duration>.Instant().duration(to: clock.now).components
            return origin.addingTimeInterval(Double(elapsed.seconds) + Double(elapsed.attoseconds) * 1e-18)
        })
        let expected = 1

        for number in 0 ..< 5 {
            sut.track(Tapped(number: number))
            await clock.advance(by: .seconds(50))
        }
        await sut.finish()

        var keys: Set<UUID?> = []
        for await record in sut.records {
            keys.insert(record.context[SessionKey.self])
        }
        let actual = keys.count
        #expect(actual == expected)
    }

    @Test("An event stamped before the session's last, as a clock set back stamps one, stays in the session and doesn't move its end back")
    func clockSetBack() async {
        let origin = Date(timeIntervalSinceReferenceDate: 1_000)
        let times = [origin.addingTimeInterval(100), origin, origin.addingTimeInterval(150)]
        let index = TestClock()
        let sut = Tracker(enrichers: [.sessions(timeout: .seconds(60))], now: {
            times[Int(TestClock<Duration>.Instant().duration(to: index.now).components.seconds)]
        })
        let expected = ["SessionStarted()", "Tapped(number: 1)", "Tapped(number: 2)", "Tapped(number: 3)"]

        sut.track(Tapped(number: 1))
        await index.advance(by: .seconds(1))
        sut.track(Tapped(number: 2))
        await index.advance(by: .seconds(1))
        sut.track(Tapped(number: 3))
        await sut.finish()

        var actual: [String] = []
        for await record in sut.records {
            actual.append(String(describing: record.event))
        }
        #expect(actual == expected)
    }

    @Test("Returning from the background past the timeout starts a new session with the open; returning sooner keeps it")
    func returnFromBackground() async throws {
        let clock = TestClock()
        let origin = Date(timeIntervalSinceReferenceDate: 1_000)
        let timeout = Duration.seconds(60)
        let sut = Tracker(enrichers: [.sessions(timeout: timeout, kinds: [])], now: {
            let elapsed = TestClock<Duration>.Instant().duration(to: clock.now).components
            return origin.addingTimeInterval(Double(elapsed.seconds) + Double(elapsed.attoseconds) * 1e-18)
        })

        sut.track(ApplicationBackgrounded())
        await clock.advance(by: timeout - .seconds(1))
        sut.track(ApplicationOpened(fromBackground: true))
        sut.track(ApplicationBackgrounded())
        await clock.advance(by: timeout)
        sut.track(ApplicationOpened(fromBackground: true))
        await sut.finish()

        var keys: [UUID?] = []
        for await record in sut.records {
            keys.append(record.context[SessionKey.self])
        }
        let first = try #require(keys[0])
        let second = try #require(keys[3])
        #expect(keys == [first, first, first, second])
        #expect(first != second)
    }

    @Test("Events tracked through an enriched copy, or a tracker bound with withTracker, carry the session too")
    func everyCopy() async {
        let sut = Tracker(enrichers: [.sessions(kinds: [])])
        let copy = sut.enriched(by: Enricher { _ in })

        sut.track(Tapped(number: 1))
        copy.track(Tapped(number: 2))
        withTracker(sut) {
            Tracker.current.track(Tapped(number: 3))
        }
        await sut.finish()

        var keys: [UUID?] = []
        for await record in sut.records {
            keys.append(record.context[SessionKey.self])
        }
        #expect(keys.count == 3)
        #expect(Set(keys).count == 1)
        #expect(!keys.contains(nil))
    }

    enum ScreenKey: ServiceContextKey {
        typealias Value = String
    }

    enum StageKey: ServiceContextKey {
        typealias Value = String
    }

    @Test("Session events carry the context the event that ended the session had, and the enrichers after the sessions one run on them")
    func sessionEventsContext() async {
        let clock = TestClock()
        let origin = Date(timeIntervalSinceReferenceDate: 1_000)
        let before = Enricher { $0[ScreenKey.self] = "screen of \($0[SessionKey.self] == nil ? "none" : "a session")" }
        let after = Enricher { $0[StageKey.self] = "after \($0[SessionKey.self] == nil ? "none" : "a session")" }
        let sut = Tracker(enrichers: [before, .sessions(timeout: .seconds(60)), after], now: {
            let elapsed = TestClock<Duration>.Instant().duration(to: clock.now).components
            return origin.addingTimeInterval(Double(elapsed.seconds) + Double(elapsed.attoseconds) * 1e-18)
        })
        let expectedScreens: [String?] = Array(repeating: "screen of none", count: 5)
        let expectedStages: [String?] = Array(repeating: "after a session", count: 5)

        sut.track(Tapped(number: 1))
        await clock.advance(by: .seconds(60))
        sut.track(Tapped(number: 2))
        await sut.finish()

        var screens: [String?] = []
        var stages: [String?] = []
        for await record in sut.records {
            screens.append(record.context[ScreenKey.self])
            stages.append(record.context[StageKey.self])
        }
        #expect(screens == expectedScreens)
        #expect(stages == expectedStages)
    }

    @Test("Session events carry the call site that made the enricher")
    func sessionEventsCallSite() async throws {
        let line = #line + 1
        let sut = Tracker(enrichers: [.sessions()])
        let expectedFileID = #fileID
        let expectedFunction = #function

        sut.track(Tapped(number: 1))
        await sut.finish()

        var records = sut.records.makeAsyncIterator()
        let actual = try #require(await records.next()?.sourceLocation)
        #expect(actual.fileID == expectedFileID)
        #expect(actual.function == expectedFunction)
        #expect(actual.line == line)
    }
}
