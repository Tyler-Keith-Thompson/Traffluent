# ``LoggingDestinations``

A destination that writes each tracked event to a swift-log `Logger`.

## Overview

``LoggerDestination`` turns each record into one log entry at the level you choose, `info` by
default. The message is the event's name. The metadata holds the event's description under
`event`, the time it was tracked under `event.timestamp`, its call site under OpenTelemetry's
`code.*` names, and every value of its `ServiceContext` under the value's key name. The entry's
own file, function and line are the event's call site, so a handler that prints them points at
the `track` call rather than at this module.

Use it to see what is tracked beside the rest of your logs, in development or in a log pipeline
you already run. It writes the event's description, in which a `Sensitive` property prints as
`<redacted>`. To add events to traces instead, use `SpanEventDestination` in the
`TracingDestinations` module; to send them to a server, `HTTPDestination` in `HTTPDestinations`.

```swift
let tracker = Tracker()
let delivery = tracker.records.batch().deliver(
    to: LoggerDestination(logger: logger, level: .debug)
)
tracker.track(SignedUp(plan: "pro"))
await tracker.finish()
try await delivery.execute()
```

The umbrella guide on this area is
[Choosing Destinations](https://tyler-keith-thompson.github.io/Traffluent/documentation/traffluent/choosingdestinations).

## Topics

### Destinations

- ``LoggerDestination``
