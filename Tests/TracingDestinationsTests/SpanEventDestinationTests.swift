import Destinations
import Events
import Foundation
import InMemoryTracing
import Instrumentation
import Testing
import Trackers
import Tracing
import TracingDestinations

@Suite("SpanEventDestination", .timeLimit(.minutes(1)))
struct SpanEventDestinationTests {
    struct SignedUp: Event {
        var plan: String
    }

    @Test("An event joins the span that was active when it was tracked, not the one active when it is delivered")
    func trackTimeSpan() async throws {
        let tracer = InMemoryTracer()
        let sut = SpanEventDestination(tracer: tracer)
        let tracker = Tracker()
        let tracked = tracer.startSpan("checkout")
        let delivering = tracer.startSpan("upload")
        let expected = ["SignedUp"]

        ServiceContext.withValue(tracked.context) {
            tracker.track(SignedUp(plan: "pro"))
        }
        await tracker.finish()
        try await ServiceContext.withValue(delivering.context) {
            try await tracker.records.batch().deliver(to: sut).execute()
        }
        tracked.end()
        delivering.end()

        let spans = tracer.finishedSpans
        let actualTracked = try #require(spans.first { $0.operationName == "checkout" }).events.map(\.name)
        let actualDelivering = try #require(spans.first { $0.operationName == "upload" }).events
        #expect(actualTracked == expected)
        #expect(actualDelivering.isEmpty)
    }

    @Test("A span event carries the time the event was tracked, its description and its call site")
    func attributes() async throws {
        let tracer = InMemoryTracer()
        let sut = SpanEventDestination(tracer: tracer)
        let tracker = Tracker(now: { Date(timeIntervalSince1970: 1_700_000_000) })
        let span = tracer.startSpan("checkout")
        let expectedNanoseconds: UInt64 = 1_700_000_000_000_000_000
        var expectedAttributes = SpanAttributes()
        expectedAttributes["event"] = "SignedUp(plan: \"pro\")"
        expectedAttributes["code.filepath"] = "M/A.swift"
        expectedAttributes["code.function"] = "f()"
        expectedAttributes["code.lineno"] = Int64(4)
        expectedAttributes["code.column"] = Int64(2)

        ServiceContext.withValue(span.context) {
            tracker.track(SignedUp(plan: "pro"), file: "/x/A.swift", fileID: "M/A.swift", function: "f()", line: 4, column: 2)
        }
        await tracker.finish()
        try await tracker.records.batch().deliver(to: sut).execute()
        span.end()

        let event = try #require(tracer.finishedSpans.first?.events.first)
        #expect(event.nanosecondsSinceEpoch == expectedNanoseconds)
        #expect(event.attributes == expectedAttributes)
    }

    @Test("A span event of a record whose call site was dropped carries no code attributes")
    func droppedCallSite() async throws {
        let tracer = InMemoryTracer()
        let sut = SpanEventDestination(tracer: tracer).droppingCallSite()
        let tracker = Tracker()
        let span = tracer.startSpan("checkout")
        var expectedAttributes = SpanAttributes()
        expectedAttributes["event"] = "SignedUp(plan: \"pro\")"

        ServiceContext.withValue(span.context) {
            tracker.track(SignedUp(plan: "pro"), file: "/x/A.swift", fileID: "M/A.swift", function: "f()", line: 4, column: 2)
        }
        await tracker.finish()
        try await tracker.records.batch().deliver(to: sut).execute()
        span.end()

        let event = try #require(tracer.finishedSpans.first?.events.first)
        #expect(event.attributes == expectedAttributes)
    }

    @Test("Events of one batch join their own spans, in the order tracked")
    func manySpans() async throws {
        let tracer = InMemoryTracer()
        let sut = SpanEventDestination(tracer: tracer)
        let tracker = Tracker()
        let first = tracer.startSpan("first")
        let second = tracer.startSpan("second")
        let expectedFirst = ["SignedUp(plan: \"a\")", "SignedUp(plan: \"c\")"]
        let expectedSecond = ["SignedUp(plan: \"b\")"]

        ServiceContext.withValue(first.context) { tracker.track(SignedUp(plan: "a")) }
        ServiceContext.withValue(second.context) { tracker.track(SignedUp(plan: "b")) }
        ServiceContext.withValue(first.context) { tracker.track(SignedUp(plan: "c")) }
        await tracker.finish()
        try await tracker.records.batch().deliver(to: sut).execute()
        first.end()
        second.end()

        func descriptions(_ name: String) -> [String] {
            (tracer.finishedSpans.first { $0.operationName == name }?.events ?? []).map {
                if case .string(let value) = $0.attributes["event"]?.toSpanAttribute() { value } else { "" }
            }
        }
        #expect(descriptions("first") == expectedFirst)
        #expect(descriptions("second") == expectedSecond)
    }

    @Test("An event tracked outside any span, or whose span has ended, is left out")
    func noSpan() async throws {
        let tracer = InMemoryTracer()
        let sut = SpanEventDestination(tracer: tracer)
        let tracker = Tracker()
        let ended = tracer.startSpan("ended")

        tracker.track(SignedUp(plan: "none"))
        ServiceContext.withValue(ended.context) { tracker.track(SignedUp(plan: "late")) }
        ended.end()
        await tracker.finish()
        try await tracker.records.batch().deliver(to: sut).execute()

        let actual = try #require(tracer.finishedSpans.first).events
        #expect(actual.isEmpty)
    }

    @Test("A time before 1970 is stamped as the epoch")
    func beforeEpoch() async throws {
        let tracer = InMemoryTracer()
        let sut = SpanEventDestination(tracer: tracer)
        let tracker = Tracker(now: { Date(timeIntervalSince1970: -5) })
        let span = tracer.startSpan("checkout")
        let expected: UInt64 = 0

        ServiceContext.withValue(span.context) { tracker.track(SignedUp(plan: "pro")) }
        await tracker.finish()
        try await tracker.records.batch().deliver(to: sut).execute()
        span.end()

        let actual = try #require(tracer.finishedSpans.first?.events.first).nanosecondsSinceEpoch
        #expect(actual == expected)
    }
}
