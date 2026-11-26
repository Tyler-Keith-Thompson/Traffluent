# ``PostHogEncoding``

Write batches of records for PostHog's batch capture API, for an `HTTPDestination` to send.

## Overview

``PostHogBatchEncoder`` is the `BatchEncoder` for PostHog Cloud's or a self-hosted PostHog's
`POST /batch/`. Give it to an `HTTPDestination` (module ``/HTTPDestinations``) as its encoder, with
your instance's `/batch/` URL. The project token goes in the body, so no header field is needed.
`import Traffluent` leaves this module out; import it on its own.

Each record becomes an anonymous event. Its `distinct_id` is the record's session, from the
sessions enricher, also sent as `$session_id`; a record with no session is sent under its own
record identifier. Its `uuid` is the record's identifier, which a redelivered record keeps. Every
event carries `$process_person_profile: false` and `$geoip_disable: true`. The record's vendor
identifier and trace context aren't sent, and the standard context is sent as PostHog's own
properties (`$app_version`, `$device_model`, `$os_name` and the like).

Properties are read through the event's schema in the `TrackingPlan` the encoder is made with. A
`Sensitive` value is never sent, whatever the record reveals, and a property whose name starts with
`$` or is `distinct_id` is left out and logged. A record the encoder can't write is left out and
the rest of the batch is sent: one the plan doesn't describe, one whose event name starts with `$`,
one whose event isn't `BinaryCodable` and one holding a value JSON can't.
``PostHogBatchEncoder/batch(of:)`` returns each as a ``PostHogSkippedRecord``.

To send to TraffluentCollector, use `CollectorBatchEncoder` (module `CollectorEncoding`)
instead.

```swift
import HTTPDestinations
import Instrumentation
import PostHogEncoding
import TrackingPlans

let plan = try TrackingPlan(schemas: [SignedUp.schema, SessionStarted.schema, SessionEnded.schema])
let encoder = PostHogBatchEncoder(projectToken: projectToken, plan: plan)
let postHog = HTTPDestination(
    endpoint: postHogBatchURL,  // https://us.i.posthog.com/batch/, https://eu.i.posthog.com/batch/ or your own
    instrument: NoOpInstrument(),  // so no trace context goes to PostHog in the header fields
    encoder: encoder)
let tracker = Tracker(enrichers: [.sessions()])
let delivery = tracker.records.batch().deliver(to: postHog)
```

The guide [Choosing Destinations](https://tyler-keith-thompson.github.io/Traffluent/documentation/traffluent/choosingdestinations)
covers what PostHog receives, and why, in more detail.

## Topics

### Encoding batches

- ``PostHogBatchEncoder``
- ``PostHogBatch``

### Records left out

- ``PostHogSkippedRecord``
- ``PostHogEncodingError``
