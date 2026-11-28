# ``HeapEncoding``

Send records to Heap as custom events, through its server-side bulk track API.

## Overview

``HTTPDestinations/HTTPDestination/heap(appID:region:plan:backoff:clock:)`` makes an
`HTTPDestination` (module ``/HTTPDestinations``) for Heap in one call. It checks your
environment's app ID, then posts to the track endpoint of your project's data center,
`https://heapanalytics.com/api/track` or, for the EU, `https://c.eu.heap-api.com/api/track`, with
a ``HeapBatchEncoder``. Each batch is split to ``HeapBatchEncoder/batchLimit``: 1,000 events a
request, the most Heap's bulk track API takes, and 1,000,000 bytes a request, the encoder's own
bound, as Heap documents none. A batch with no record the encoder can write, an empty one
included, makes no request. The destination retries no response, a 5xx, 408 and 429, and drops and
reports any other status. No trace context is sent. `import Traffluent` leaves this module out, so
import it on its own.

Heap's server-side API complements its SDKs: Heap says "you can only send events to identified
users". Every user this destination makes has only server-side events, and Heap treats such a user
differently from one its SDKs capture:

- the user's profile says its events are hidden, and Heap lists them under the Hidden Events
  category of its Events tab;
- the events aren't sessionized, so Heap's Sessions list stays empty for them;
- a session filter on a user property sees only SDK sessions, so it matches none of them.

So checking that events reach Heap's Live data feed isn't enough: after setting the destination
up, confirm that its events appear in the charts and reports you mean to use.

The track API takes the app ID alone, which Heap's own SDKs ship inside every app, and no API key,
so the destination builds on every platform and an app sends to Heap directly. Heap's API key is
for its user deletion API, which this module doesn't call; don't put one in an app.

```swift
import HTTPDestinations
import HeapEncoding
import TrackingPlans

let plan = try TrackingPlan()
let heap = try HTTPDestination.heap(
    appID: appID,  // the environment's ID, from Heap's project settings
    region: .us,  // or .eu, where the project's data resides
    plan: plan)
let tracker = Tracker(enrichers: [.sessions()])
let delivery = tracker.records.batch().deliver(to: heap)
```

The factory throws ``HeapSetupError`` for an app ID that is empty or only whitespace, and for one
holding anything but ASCII digits: a Heap environment's ID is a number, such as `12343283`.
`region` has no default. Pass ``HeapRegion/eu`` when your project's data is in Heap's EU data
center.

### Users are sessions

Heap files each event under its `identity`, and makes a user for each identity it hasn't seen. The
destination sends the record's session, from the sessions enricher, as the identity: its
`SessionKey` as a lowercase UUID. Nothing else identifies a record: no `user_id`, `session_id`,
vendor identifier, device identifier or account, and no trace context.

So Heap's users are sessions. A person who opens the app three times is three users, and Heap's
retention and user counts describe sessions, not people. That is the library's default, for
privacy. To count
devices or accounts instead, write your own enricher and encoder that send the identifier you
choose; this encoder sends the session alone.

A record with no session, from a tracker without the sessions enricher, is its own user: its
identity is the record's identifier. A record a store recovered after a relaunch keeps its session. Making up a session would join unrelated records, skipping
the record would lose it, and Heap takes no event without an identity.

### What Heap receives

Each request is a JSON object: `app_id`, as given, without surrounding whitespace, and `events`,
one track event per record. Every event has:

- `event`, the event's name;
- `identity`, the session;
- `idempotency_key`, the record's identifier, so Heap stores a record sent twice under the same
  identity once. A record a store recovers after a relaunch keeps its session, so it goes under
  the identity of its first send, and Heap stores it once;
- `timestamp`, the record's timestamp in ISO 8601 with milliseconds, so an event sent late still
  counts at the time it was tracked;
- `properties`, when the event has any to send.

The record's properties are read through the event's schema in the `TrackingPlan` the encoder is
made with. Heap takes a number or a string as a property's value, so an object or array is
flattened into dotted names: a `cart` holding `size` is `cart.size`, and the first element of
`tags` is `tags.0`. A boolean is the string `true` or `false`, a number keeps its JSON type, and a
`nil` property is left out. A `Sensitive` value is never sent, whatever the record reveals.

The standard context isn't sent. Heap keeps no built-in property of an event sent through its
server-side API, so the app's version or the device's model would sit among the event's own
properties, where they could collide with your own names.

### Records left out

A record the encoder can't write is left out and the rest of the batch is sent:

- one the plan doesn't describe, whose event isn't `Encodable`, or that holds a value JSON can't;
- one whose event name is longer than the 1,024 characters Heap takes;
- one with a property named `user_id`, `session_id` or `screen_name`, which Heap reserves: the
  first two are fields of a track request, and the last is the screen name its mobile SDKs
  capture. A name like one, such as `User_id` or `screen_name.0`, is sent.
- one with a property, once flattened, whose name or string value is 1,024 characters or more:
  Heap takes fewer. Characters are counted in UTF-16, as JavaScript counts them, so an emoji
  counts two.
- one whose values flatten to the same name twice;
- one whose timestamp falls outside the years 1 to 9999, which have no four-digit ISO 8601 year;
- one too large for a request of 1,000,000 bytes on its own.

The destination reports each as `HTTPDropReport.skipped(_:)`, a `SkippedRecord` whose reason is a
``HeapEncodingError``. When the destination is made, it logs a notice for each event and property
of the plan whose name would be left out.

### What Heap doesn't report

Heap answers 200 to a request it takes and 400 to one it can't, which the destination drops and
reports with every record of the request. Its docs don't say what it answers to an app ID of no
environment, so confirm that the first events appear in your charts after setting it up.

Heap takes 15,000 events a minute from one environment, and every device sending to it shares
that limit: at a steady rate it is about 21.6 million events a day across all your users, and a
burst, such as many devices sending their backlogs at once, reaches it sooner. Heap's docs don't
say what it answers past the limit. If it answers 429, the destination retries the request on its
backoff, with full jitter, so devices refused together retry at different moments. It doesn't
read `Retry-After`, though, so a backlog can still grow. If it answers 400, the destination drops
the whole request and reports it as rejected, and its records are lost.

Heap also takes 30 requests in 30 seconds and 1,000 events a minute from one identity, which is
one session here. A session whose own backlog holds more than 1,000 events, such as one that ran
long offline, goes past it when it sends, with the same outcomes. A smaller batch wouldn't avoid
that, as the destination doesn't pace its requests, so requests keep Heap's bulk maximum of 1,000
events.

Events sent through the server-side API carry only the properties sent with them.

The guide [Choosing Destinations](https://tyler-keith-thompson.github.io/Traffluent/documentation/traffluent/choosingdestinations)
covers what Heap receives, and why, in more detail.

## Topics

### Sending to Heap

- ``HTTPDestinations/HTTPDestination/heap(appID:region:plan:backoff:clock:)``
- ``HTTPDestinations/HTTPDestination/heap(appID:region:plan:transport:backoff:clock:)``
- ``HeapRegion``
- ``HeapSetupError``

### Encoding batches

- ``HeapBatchEncoder``

### Records left out

- ``HeapEncodingError``
