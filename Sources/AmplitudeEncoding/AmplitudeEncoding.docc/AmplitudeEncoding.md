# ``AmplitudeEncoding``

Send records to an Amplitude project through its HTTP V2 API.

## Overview

``HTTPDestinations/HTTPDestination/amplitude(apiKey:region:plan:backoff:clock:)`` makes an
`HTTPDestination` (module ``/HTTPDestinations``) for your Amplitude project in one call. It checks
the API key, posts to the HTTP V2 endpoint of the project's data residency (``AmplitudeRegion``)
with an ``AmplitudeBatchEncoder``, and splits each batch to Amplitude's limits
(``AmplitudeBatchEncoder/batchLimit``): 10 events and 1 MB a request, which a project on any plan
accepts. A batch with no record the encoder can write, an empty one included, makes no request. It
retries no response, a 5xx, 408 and 429, and drops and reports any other status. The API key goes
in the body, so no header field is needed, and no trace context is sent. `import Traffluent`
leaves this module out; import it on its own.

The region has no default. A project's data resides in Amplitude's default data center or its EU
one, and an event posted to the other doesn't reach it, so you pick the region on purpose. The
factory throws ``AmplitudeSetupError`` for an empty key, and for an Amplitude Experiment deployment
key, which isn't the project's API key.

Each record becomes an event of an anonymous device. Its `device_id` is the record's session,
from the sessions enricher, and its `session_id` that session's start in Unix milliseconds; a
record with no session is sent under its own record identifier, with no `session_id`. No `user_id`
is sent. Its `insert_id` is the record's identifier, which a redelivered record keeps, and its
`time` the record's timestamp in epoch milliseconds. The record's vendor identifier and trace
context aren't sent, nor is an `ip`, and the standard context is sent as Amplitude's own fields
(`app_version`, `device_model`, `language`, `platform`, `os_name` and `os_version`).

Amplitude counts a user per `device_id` and bills by monthly tracked users, so each session counts
as one tracked user, and so does each record sent without a session.

Properties are read through the event's schema in the `TrackingPlan` the encoder is made with, into
`event_properties`. A `Sensitive` value is never sent, whatever the record reveals. A record the
encoder can't write is left out and the rest of the batch is sent: one the plan doesn't describe,
one whose event name Amplitude keeps for its own (`[Amplitude] …`, `$identify`, `$groupidentify`),
one whose event isn't `Encodable`, one holding a value JSON can't, one whose timestamp has no
epoch-milliseconds form, and one too large for a request. The destination reports each as
`HTTPDropReport.skipped(_:)`, a `SkippedRecord` whose reason is an ``AmplitudeEncodingError``.

To send to PostHog, use `PostHogEncoding` instead.

```swift
import AmplitudeEncoding
import HTTPDestinations
import TrackingPlans

let plan = try TrackingPlan()
let amplitude = try HTTPDestination.amplitude(
    apiKey: apiKey,
    region: .us,  // or .eu, where the project's data resides
    plan: plan)
let tracker = Tracker(enrichers: [.sessions()])
let delivery = tracker.records.batch().deliver(to: amplitude)
```

The guide [Choosing Destinations](https://tyler-keith-thompson.github.io/Traffluent/documentation/traffluent/choosingdestinations)
covers what Amplitude receives, and why, in more detail.

## Topics

### Sending to Amplitude

- ``HTTPDestinations/HTTPDestination/amplitude(apiKey:region:plan:backoff:clock:)``
- ``HTTPDestinations/HTTPDestination/amplitude(apiKey:region:plan:transport:backoff:clock:)``
- ``AmplitudeRegion``
- ``AmplitudeSetupError``

### Encoding batches

- ``AmplitudeBatchEncoder``

### Records left out

- ``AmplitudeEncodingError``
