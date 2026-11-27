# ``PostHogEncoding``

Send records to PostHog Cloud or a self-hosted PostHog through its batch capture API.

## Overview

``HTTPDestinations/HTTPDestination/postHog(projectToken:host:plan:backoff:clock:)`` makes an
`HTTPDestination` (module ``/HTTPDestinations``) for your PostHog project in one call. It checks
the project token and the host, posts to the host's `/batch/` with a ``PostHogBatchEncoder``, and
splits each batch to PostHog's limits (``PostHogBatchEncoder/batchLimit``). A batch with no
record the encoder can write, an empty one included, makes no request. It retries no response, a
5xx, 408 and 429, and drops and reports any other status. The project token goes in
the body, so no header field is needed, and no trace context is sent. `import Traffluent` leaves
this module out; import it on its own.

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
one whose event isn't `Encodable`, one holding a value JSON can't, and one too large for PostHog's
event limit. The destination reports each as `HTTPDropReport.skipped(_:)`, a `SkippedRecord` whose
reason is a ``PostHogEncodingError``.

To send to TraffluentCollector, use `CollectorBatchEncoder` (module `CollectorEncoding`)
instead.

```swift
import HTTPDestinations
import PostHogEncoding
import TrackingPlans

let plan = try TrackingPlan(schemas: [SignedUp.schema, SessionStarted.schema, SessionEnded.schema])
let postHog = try HTTPDestination.postHog(
    projectToken: projectToken,
    host: postHogHost,  // https://us.i.posthog.com, https://eu.i.posthog.com or your own
    plan: plan)
let tracker = Tracker(enrichers: [.sessions()])
let delivery = tracker.records.batch().deliver(to: postHog)
```

The guide [Choosing Destinations](https://tyler-keith-thompson.github.io/Traffluent/documentation/traffluent/choosingdestinations)
covers what PostHog receives, and why, in more detail.

## Topics

### Sending to PostHog

- ``HTTPDestinations/HTTPDestination/postHog(projectToken:host:plan:backoff:clock:)``
- ``HTTPDestinations/HTTPDestination/postHog(projectToken:host:plan:transport:backoff:clock:)``
- ``PostHogSetupError``

### Encoding batches

- ``PostHogBatchEncoder``

### Records left out

- ``PostHogEncodingError``
