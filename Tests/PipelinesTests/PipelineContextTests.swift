import Destinations
import Events
import InMemoryTracing
import Instrumentation
import Pipelines
import Synchronization
import Testing
import Tracing

@Suite("Pipeline: context and enrichers", .timeLimit(.minutes(1)))
struct PipelineContextTests {
    struct Tapped: Event {
        var number: Int
    }

    enum SessionKey: ServiceContextKey {
        typealias Value = String
    }

    enum ScreenKey: ServiceContextKey {
        typealias Value = String
    }

    /// Records every record it receives, in order.
    final class Recorder: Destination {
        let records = Mutex<[EventRecord]>([])

        func receive(_ batch: [EventRecord]) async {
            records.withLock { $0.append(contentsOf: batch) }
        }
    }

    @Test("A record carries the ServiceContext the event was tracked in")
    func snapshot() async throws {
        let recorder = Recorder()
        let sut = Pipeline(recorder)
        var context = ServiceContext.topLevel
        context[SessionKey.self] = "s-1"
        let expected = "s-1"

        ServiceContext.withValue(context) {
            sut.track(Tapped(number: 1))
        }
        sut.finish()
        try await sut.run().execute()

        let actual = try #require(recorder.records.withLock { $0.first }).context[SessionKey.self]
        #expect(actual == expected)
    }

    @Test("With no context bound, a record's context is empty")
    func unbound() async throws {
        let recorder = Recorder()
        let sut = Pipeline(recorder)

        sut.track(Tapped(number: 1))
        sut.finish()
        try await sut.run().execute()

        let actual = try #require(recorder.records.withLock { $0.first }).context[SessionKey.self]
        #expect(actual == nil)
    }

    @Test("The context is taken when the event is tracked, not when it is delivered")
    func takenAtTrackTime() async throws {
        let recorder = Recorder()
        let sut = Pipeline(recorder)
        var first = ServiceContext.topLevel
        first[SessionKey.self] = "s-1"
        var second = ServiceContext.topLevel
        second[SessionKey.self] = "s-2"
        let expected = ["s-1", "s-2"]

        ServiceContext.withValue(first) { sut.track(Tapped(number: 1)) }
        ServiceContext.withValue(second) { sut.track(Tapped(number: 2)) }
        sut.finish()
        try await sut.run().execute()

        let actual = recorder.records.withLock { $0.map { $0.context[SessionKey.self] } }
        #expect(actual == expected)
    }

    @Test("Enrichers add typed values to every record's context")
    func enriches() async throws {
        let recorder = Recorder()
        let screen = Enricher { $0[ScreenKey.self] = "Home" }
        let sut = Pipeline(recorder, enrichers: [screen])
        let expected = ["Home", "Home"]

        sut.track(Tapped(number: 1))
        sut.track(Tapped(number: 2))
        sut.finish()
        try await sut.run().execute()

        let actual = recorder.records.withLock { $0.map { $0.context[ScreenKey.self] } }
        #expect(actual == expected)
    }

    @Test("Enrichers run in order, each seeing what the caller's context and earlier enrichers set")
    func order() async throws {
        let recorder = Recorder()
        let first = Enricher { $0[ScreenKey.self] = "screen of \($0[SessionKey.self] ?? "none")" }
        let second = Enricher { $0[SessionKey.self] = "s-2" }
        let sut = Pipeline(recorder, strategy: .count(1), enrichers: [first, second])
        var context = ServiceContext.topLevel
        context[SessionKey.self] = "s-1"
        let expectedScreen = "screen of s-1"
        let expectedSession = "s-2"

        ServiceContext.withValue(context) {
            sut.track(Tapped(number: 1))
        }
        sut.finish()
        try await sut.run().execute()

        let record = try #require(recorder.records.withLock { $0.first })
        #expect(record.context[ScreenKey.self] == expectedScreen)
        #expect(record.context[SessionKey.self] == expectedSession)
    }

    @Test("An event tracked inside an active span carries that span's context")
    func span() async throws {
        let recorder = Recorder()
        let sut = Pipeline(recorder)
        let tracer = InMemoryTracer()

        let expected = tracer.withSpan("checkout") { span in
            sut.track(Tapped(number: 1))
            return span.context.inMemorySpanContext
        }
        sut.finish()
        try await sut.run().execute()

        let actual = try #require(recorder.records.withLock { $0.first }).context.inMemorySpanContext
        #expect(actual != nil)
        #expect(actual == expected)
    }
}
