# ``TracingDestinations``

A destination that adds each tracked event to the span that was active when it was tracked.

## Overview

``SpanEventDestination`` finds each record's span from the `ServiceContext` the event was tracked
in, so a delivery that runs later, under another span or none, still adds the event to the right
one. Each span event is named after the event, stamped with the time it was tracked, and carries
the event's description under `event` and its call site under OpenTelemetry's `code.*` attribute
names.

Span events can't be added to a span that has ended. A record tracked outside any span, or whose
span ended before its batch was delivered, is left out. Batch tightly enough for your spans to
outlive their batches, and deliver to another destination as well for the events that must not be
lost. To write events to your logs instead, use `LoggerDestination` in the `LoggingDestinations`
module.

```swift
let tracker = Tracker()
let delivery = tracker.records.batch().deliver(to: SpanEventDestination(tracer: tracer))
let span = tracer.startSpan("checkout")
ServiceContext.withValue(span.context) {
    tracker.track(SignedUp(plan: "pro"))
}
await tracker.finish()
try await delivery.execute()
span.end()
```

The umbrella guide on this area is
[Choosing Destinations](https://tyler-keith-thompson.github.io/Traffluent/documentation/traffluent/choosingdestinations).

## Topics

### Destinations

- ``SpanEventDestination``
