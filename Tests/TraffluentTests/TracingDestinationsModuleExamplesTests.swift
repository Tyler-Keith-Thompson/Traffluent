// The example of the TracingDestinations module's landing article
// (Sources/TracingDestinations/TracingDestinations.docc/TracingDestinations.md), verbatim, so the
// article cannot drift from the code. It runs against swift-distributed-tracing's NoOpTracer, which
// records nothing, so it checks only that the example compiles and its delivery completes;
// TracingDestinationsTests checks the span events against an InMemoryTracer.

import Instrumentation
import Testing
import Tracing
import Traffluent

// Private: its events share their names with other events of this test target, and @Event
// leaves a private type's events out of the link check of names (DefiningEvents, Limits).
@Suite("TracingDestinations module examples", .timeLimit(.minutes(1)))
private struct TracingDestinationsModuleExamplesTests {
    @Event
    struct SignedUp {
        var plan: String
    }

    @Test("A span event destination delivers the events tracked inside a span")
    func spanEventDestination() async throws {
        let tracer = NoOpTracer()

        let tracker = Tracker()
        let delivery = tracker.records.batch().deliver(to: SpanEventDestination(tracer: tracer))
        let span = tracer.startSpan("checkout")
        ServiceContext.withValue(span.context) {
            tracker.track(SignedUp(plan: "pro"))
        }
        await tracker.finish()
        try await delivery.execute()
        span.end()
    }
}
