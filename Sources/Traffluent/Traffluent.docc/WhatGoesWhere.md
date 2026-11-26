# Logging, Tracing, Metrics and Analytics

Four signals, four jobs. Decide which one a fact belongs to before you write the line that records it.

## Overview

Logs, traces, metrics and analytics events all describe what an app did, so it is tempting to
pick one and send it everything. Don't. Each has its own audience, retention, cost model and
legal basis. A fact sent to the wrong one is either lost when someone needs it, or kept where it
shouldn't be.

| Signal | Answers | Read by | Shape | In Swift |
|---|---|---|---|---|
| Logging | What did this process do, step by step? | The developer debugging it | Text with metadata. High volume, short retention, local first. May hold private data, which stays redacted. | swift-log, `os.Logger` |
| Tracing | Where did the time go in this request, across processes? | The engineer on call | Spans with parents and children, their context propagated across calls | swift-distributed-tracing, OpenTelemetry |
| Metrics (monitoring) | Is the system healthy right now? | Alerts, and whoever they page | Aggregated numbers: counters, gauges, histograms. Low cardinality. | swift-metrics |
| Analytics | What do people do, and does the product work for them? | Product, design and data teams | Typed events about a person's journey. Durable, consented, joined by user and session. | Traffluent |

### Which one is it

- **A product manager would chart it:** an analytics event.
- **An alert fires on it:** a metric.
- **You'd only read it while debugging:** a log line.
- **It's about latency across a call graph:** a span.

When a fact seems to fit two, it is usually two facts. A failed payment is a log line for the
developer (with the error and the stack), a metric for the alert (the failure rate), and an
analytics event for the product team (a checkout that ended in `CheckoutFailed(reason:
.paymentDeclined)`). Record each where it belongs. Don't record one and derive the others.

### Rules

- **Analytics events are a contract.** They are typed, versioned and reviewed like an API, because
  dashboards, experiments and other teams' queries depend on their shape. Logs are not a
  contract. Nobody should build a dashboard on a log line, and a developer should be free to
  reword one.
- **Never derive product analytics from logs.** Logs are unstructured, sampled or dropped under
  load, retained briefly, and collected without the user's analytics consent. A funnel built on
  them is wrong in ways no one can see.
- **Never put user IDs or other unbounded values in metric labels.** Every distinct label value
  is a new time series. Per-user questions are analytics questions.
- **Errors split three ways.** The crash or exception goes to crash reporting and logs, and the
  rate goes to metrics. What the user experienced is an analytics event with a typed reason,
  never the error's message: messages change between releases, are localized, and can carry
  private data.
- **Latency is a span or a metric; abandonment is an analytics event.** "The request took 3.2 s"
  is a span. "The user waited and left" is something the product team acts on.
- **Consent differs.** Analytics about a person needs their consent and stops without it.
  Operational logs, metrics and traces usually rest on keeping the service running. Mixing them
  means either asking consent for your logs or leaking analytics into them.

### Bridges

The signals stay separate, but they can point at each other:

- `LoggerDestination` (module `LoggingDestinations`) mirrors analytics events into your logs.
  Use it in development to see what is tracked beside what happened. In production, the
  analytics pipeline is the record.
- `SpanEventDestination` (module `TracingDestinations`) adds each event to the span that was
  active when it was tracked. An engineer reading a slow trace sees which user action started it.
- Every `EventRecord` carries the `ServiceContext` it was tracked in, so an analytics event and
  the trace around it share a trace ID without either system storing the other's data.
- `HTTPDestination` (module `HTTPDestinations`) injects the trace context of each batch's first
  record into its request's header fields, so a collector that extracts it records the request
  in the trace the app was in.

## Anti-patterns

### Tracking error strings

```swift
// Bad: the message is unstable, localized and may hold private data,
// and every distinct string becomes its own row in a dashboard.
@Event
struct ErrorOccurred {
    var message: String
}
tracker.track(ErrorOccurred(message: error.localizedDescription))
```

Track what the user experienced, with a reason the product team can count. Leave the error
itself to logs and crash reporting. The reason is an enum, which the event stores as its raw
value and the tracking plan lists case by case:

```swift
@Event
struct CheckoutFailed {
    enum Reason: String, Codable {
        case paymentDeclined
        case outOfStock
        case networkUnavailable
    }
    var reason: Reason
}

tracker.track(CheckoutFailed(reason: .paymentDeclined))
```

### Funnels scraped from logs

```swift
// Bad: a funnel built by searching logs for this line breaks the day
// someone rewords it, and counts only what survived log sampling.
logger.info("user tapped checkout with \(cart.count) items")
```

Log for the developer, and track the step as a typed event:

```swift
@Event
struct CheckoutStarted {
    var itemCount: Int
}

tracker.track(CheckoutStarted(itemCount: 3))
```

### Metrics labelled by user

```swift
// Bad: one time series per user. The metrics backend's cost grows with your
// user count, and per-user questions still can't be answered well.
Counter(label: "checkout.failures", dimensions: [("user", userID)]).increment()
```

Keep metric labels to small, fixed sets (the reason, the region). Answer per-user questions with
analytics, where the person is part of the event's context by design:

```swift
tracker.track(CheckoutFailed(reason: .networkUnavailable))
```

### An analytics event per network request

```swift
// Bad: request-level detail is tracing's job. Analytics volume, cost
// and consent scope balloon, and the product team gets noise.
@Event
struct RequestCompleted {
    var path: String
    var status: Int
}
tracker.track(RequestCompleted(path: "/cart", status: 200))
```

Trace the request, and track the fact the product team cares about once:

```swift
@Event
struct CartViewed {
    var itemCount: Int
}

withSpan("GET /cart") { _ in
    tracker.track(CartViewed(itemCount: 3))
}
```
