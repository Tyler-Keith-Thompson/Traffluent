# ``MixpanelEncoding``

Send records to a Mixpanel project through its track API.

## Overview

``HTTPDestinations/HTTPDestination/mixpanel(projectToken:region:plan:backoff:clock:)`` makes an
`HTTPDestination` (module ``/HTTPDestinations``) for your Mixpanel project in one call. It checks
the project token, posts to the `/track` endpoint of the project's data residency
(``MixpanelRegion``) with a ``MixpanelBatchEncoder``, and splits each batch to Mixpanel's limits
(``MixpanelBatchEncoder/batchLimit``): 2,000 events and 2 MB a request. A batch with no record the
encoder can write, an empty one included, makes no request. It retries no response, a 5xx, 408
and 429, waiting ``HTTPDestinations/ExponentialBackoff/mixpanel``: Mixpanel's recommended
schedule, 2 s doubling to 60 s. The full jitter on top is Traffluent's own choice. It drops and
reports any other status. The token goes in each event, so no header field is needed, and no
trace context is sent. `import Traffluent` leaves this module out; import it on its own.

The project token is public: Mixpanel's own apps and web pages ship it. The destination takes
nothing else. Never put the project's secret or a service account's credentials in an app; they
belong to Mixpanel's import API, for servers. The factory throws ``MixpanelSetupError`` for an
empty token, and for one with a character other than a letter or digit, which no project token
has.

The region has no default. A project's data resides in the US, the EU or India, and Mixpanel
ingests nothing for it from another residency's endpoint, so you pick the region on purpose.

Each record becomes an event of an anonymous user. Its `distinct_id` is the record's session,
from the sessions enricher, also sent as `$device_id`; a record with no session is sent under its
own record identifier, with no `$device_id`. Under Simplified ID Merge, Mixpanel shows a
session's events under `$device:<session>`, and a sessionless record's under its bare record
identifier. No `$user_id` is sent. Its `$insert_id` is the
record's identifier, which a redelivered record keeps, and its `time` the record's timestamp in
epoch milliseconds. The record's vendor identifier and trace context aren't sent. Each event's
`ip` is `0`, as is the endpoint's, so Mixpanel adds no location from the request's address. The
standard context is sent as Mixpanel's default properties (`$app_version_string`,
`$app_build_number`, `$model`, `$wifi`, `$os` and `$os_version`).

Mixpanel counts a user per `distinct_id`, so each session is one user in its reports, and so is
each record sent without a session. On a Mixpanel plan billed by monthly tracked users, each counts
as one.

Properties are read through the event's schema in the `TrackingPlan` the encoder is made with. A
`Sensitive` value is never sent, whatever the record reveals. A record the encoder can't write is
left out and the rest of the batch is sent: one the plan doesn't describe, one whose event name
starts with `$`, as Mixpanel's own events' names do, one with a property Mixpanel reads for itself
(a `$`-prefixed one, `token`, `time`, `distinct_id`, `ip` or `bucket`), one of 255 properties or
more counting the encoder's own, one holding an array of 255 elements or more, one whose property
nests objects more than 3 deep, one whose event isn't
`Encodable`, one holding a value JSON can't, one whose timestamp is before 1971 or has no
epoch-milliseconds form, and one too large for Mixpanel. The destination reports each as
`HTTPDropReport.skipped(_:)`, a `SkippedRecord` whose reason is a ``MixpanelEncodingError``.

Mixpanel answers 200 even when it ingests none of a request's events, and its track API ingests
only events from the last 5 days, so a record older than that when it is sent is counted as
delivered and not stored. A wrong region, or a token of no project, may be answered 200 with
nothing stored too, so check the project's Live View after setting the destination up.

To send to PostHog or Amplitude, use `PostHogEncoding` or `AmplitudeEncoding` instead.

```swift
import HTTPDestinations
import MixpanelEncoding
import TrackingPlans

let plan = try TrackingPlan()
let mixpanel = try HTTPDestination.mixpanel(
    projectToken: projectToken,
    region: .us,  // or .eu or .india, where the project's data resides
    plan: plan)
let tracker = Tracker(enrichers: [.sessions()])
let delivery = tracker.records.batch().deliver(to: mixpanel)
```

The guide [Choosing Destinations](https://tyler-keith-thompson.github.io/Traffluent/documentation/traffluent/choosingdestinations)
covers what Mixpanel receives, and why, in more detail.

## Topics

### Sending to Mixpanel

- ``HTTPDestinations/HTTPDestination/mixpanel(projectToken:region:plan:backoff:clock:)``
- ``HTTPDestinations/HTTPDestination/mixpanel(projectToken:region:plan:transport:backoff:clock:)``
- ``MixpanelRegion``
- ``HTTPDestinations/ExponentialBackoff/mixpanel``
- ``MixpanelSetupError``

### Encoding batches

- ``MixpanelBatchEncoder``

### Records left out

- ``MixpanelEncodingError``
