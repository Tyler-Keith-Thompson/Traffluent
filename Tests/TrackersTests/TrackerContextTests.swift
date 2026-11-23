import Foundation
import Events
import InMemoryTracing
import Instrumentation
import Testing
import Trackers
import Tracing

@Suite("Tracker: context and enrichers", .timeLimit(.minutes(1)))
struct TrackerContextTests {
    struct Tapped: Event {
        var number: Int
    }

    enum SessionKey: ServiceContextKey {
        typealias Value = String
    }

    enum ScreenKey: ServiceContextKey {
        typealias Value = String
    }

    @Test("A record carries the ServiceContext the event was tracked in")
    func snapshot() async throws {
        let sut = Tracker()
        var context = ServiceContext.topLevel
        context[SessionKey.self] = "s-1"
        let expected = "s-1"

        ServiceContext.withValue(context) {
            sut.track(Tapped(number: 1))
        }
        await sut.finish()

        var records = sut.records.makeAsyncIterator()
        let actual = try #require(await records.next()).context[SessionKey.self]
        #expect(actual == expected)
    }

    @Test("With no context bound, a record's context is empty")
    func unbound() async throws {
        let sut = Tracker()

        sut.track(Tapped(number: 1))
        await sut.finish()

        var records = sut.records.makeAsyncIterator()
        let actual = try #require(await records.next()).context[SessionKey.self]
        #expect(actual == nil)
    }

    @Test("The context is taken when the event is tracked, not when it is read")
    func takenAtTrackTime() async {
        let sut = Tracker()
        var first = ServiceContext.topLevel
        first[SessionKey.self] = "s-1"
        var second = ServiceContext.topLevel
        second[SessionKey.self] = "s-2"
        let expected = ["s-1", "s-2"]

        ServiceContext.withValue(first) { sut.track(Tapped(number: 1)) }
        ServiceContext.withValue(second) { sut.track(Tapped(number: 2)) }
        await sut.finish()

        var actual: [String?] = []
        for await record in sut.records {
            actual.append(record.context[SessionKey.self])
        }
        #expect(actual == expected)
    }

    @Test("Enrichers add typed values to every record's context")
    func enriches() async {
        let screen = Enricher { $0[ScreenKey.self] = "Home" }
        let sut = Tracker(enrichers: [screen])
        let expected = ["Home", "Home"]

        sut.track(Tapped(number: 1))
        sut.track(Tapped(number: 2))
        await sut.finish()

        var actual: [String?] = []
        for await record in sut.records {
            actual.append(record.context[ScreenKey.self])
        }
        #expect(actual == expected)
    }

    @Test("Enrichers run in order, each seeing what the caller's context and earlier enrichers set")
    func order() async throws {
        let first = Enricher { $0[ScreenKey.self] = "screen of \($0[SessionKey.self] ?? "none")" }
        let second = Enricher { $0[SessionKey.self] = "s-2" }
        let sut = Tracker(enrichers: [first, second])
        var context = ServiceContext.topLevel
        context[SessionKey.self] = "s-1"
        let expectedScreen = "screen of s-1"
        let expectedSession = "s-2"

        ServiceContext.withValue(context) {
            sut.track(Tapped(number: 1))
        }
        await sut.finish()

        var records = sut.records.makeAsyncIterator()
        let record = try #require(await records.next())
        #expect(record.context[ScreenKey.self] == expectedScreen)
        #expect(record.context[SessionKey.self] == expectedSession)
    }

    @Test("An event tracked inside an active span carries that span's context")
    func span() async throws {
        let sut = Tracker()
        let tracer = InMemoryTracer()

        let expected = tracer.withSpan("checkout") { span in
            sut.track(Tapped(number: 1))
            return span.context.inMemorySpanContext
        }
        await sut.finish()

        var records = sut.records.makeAsyncIterator()
        let actual = try #require(await records.next()).context.inMemorySpanContext
        #expect(actual != nil)
        #expect(actual == expected)
    }

    @Test("An enriched copy's events carry what its enricher sets; the original's don't")
    func enrichedCopy() async {
        let tracker = Tracker()
        let sut = tracker.enriched(by: Enricher { $0[ScreenKey.self] = "Checkout" })
        let expected: [String?] = ["Checkout", nil]

        sut.track(Tapped(number: 1))
        tracker.track(Tapped(number: 2))
        await tracker.finish()

        var actual: [String?] = []
        for await record in tracker.records {
            actual.append(record.context[ScreenKey.self])
        }
        #expect(actual == expected)
    }

    @Test("A copy's enricher runs on the caller's context, before the tracker's enrichers, which see what it set")
    func enrichedCopyBeforeTrackerEnrichers() async throws {
        let session = Enricher { $0[SessionKey.self] = "session on \($0[ScreenKey.self] ?? "none")" }
        let tracker = Tracker(enrichers: [session])
        let sut = tracker.enriched(by: Enricher { $0[ScreenKey.self] = "Checkout from \($0[SessionKey.self] ?? "none")" })
        var context = ServiceContext.topLevel
        context[SessionKey.self] = "s-1"
        let expectedScreen = "Checkout from s-1"
        let expectedSession = "session on Checkout from s-1"

        ServiceContext.withValue(context) {
            sut.track(Tapped(number: 1))
        }
        await tracker.finish()

        var records = tracker.records.makeAsyncIterator()
        let record = try #require(await records.next())
        #expect(record.context[ScreenKey.self] == expectedScreen)
        #expect(record.context[SessionKey.self] == expectedSession)
    }

    @Test("Enriching a copy again keeps its enricher and runs the new one after it")
    func enrichedTwice() async throws {
        let outer = Tracker().enriched(by: Enricher {
            $0[SessionKey.self] = "s-1"
            $0[ScreenKey.self] = "Home"
        })
        let sut = outer.enriched(by: Enricher { $0[ScreenKey.self] = "Checkout" })
        let expectedScreen = "Checkout"
        let expectedSession = "s-1"

        sut.track(Tapped(number: 1))
        await sut.finish()

        var records = sut.records.makeAsyncIterator()
        let record = try #require(await records.next())
        #expect(record.context[ScreenKey.self] == expectedScreen)
        #expect(record.context[SessionKey.self] == expectedSession)
    }

    @Test("A no-op tracker's enriched copy drops every event")
    func enrichedNoOp() async {
        let sut = Tracker.noOp.enriched(by: Enricher { $0[ScreenKey.self] = "Checkout" })
        let expected = 0

        sut.track(Tapped(number: 1))
        await sut.finish()

        var actual = 0
        for await _ in sut.records {
            actual += 1
        }
        #expect(actual == expected)
    }

    @Test("An enriched copy stamps its events with the tracker's clock")
    func enrichedCopyClock() async throws {
        let expected = Date(timeIntervalSince1970: 1_000)
        let sut = Tracker(now: { expected }).enriched(by: Enricher { $0[ScreenKey.self] = "Checkout" })

        sut.track(Tapped(number: 1))
        await sut.finish()

        var records = sut.records.makeAsyncIterator()
        let actual = try #require(await records.next()).timestamp
        #expect(actual == expected)
    }
}
