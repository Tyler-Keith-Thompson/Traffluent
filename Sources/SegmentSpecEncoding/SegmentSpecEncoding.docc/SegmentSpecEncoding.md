# ``SegmentSpecEncoding``

Send records as Segment-spec track calls to Segment, RudderStack or Customer.io Data Pipelines.

## Overview

Segment, RudderStack and Customer.io Data Pipelines each take the same batch call of the Segment
spec, at endpoints of their own. One encoder, ``SegmentSpecBatchEncoder``, writes it, and a
factory for each fills in the endpoint and how the key travels:

- ``HTTPDestinations/HTTPDestination/segment(writeKey:region:plan:backoff:clock:)`` posts to the
  `/v1/batch` of the workspace's region (``SegmentRegion``), with the write key as HTTP Basic
  authentication's user name and an empty password.
- ``HTTPDestinations/HTTPDestination/rudderStack(writeKey:dataPlane:plan:backoff:clock:)`` posts to
  the `/v1/batch` of your data plane URL, with the write key the same way.
- ``HTTPDestinations/HTTPDestination/customerIO(apiKey:region:plan:backoff:clock:)`` posts to the
  Pipelines API's `/v1/batch` in the workspace's region (``CustomerIORegion``), with the key as a
  bearer token and `X-Strict-Mode: 1`.

Each splits a batch to the spec's limits (``SegmentSpecBatchEncoder/batchLimit``): 2,500 calls
and 500 KB a request, and under 32 KB a call, which all three accept. A batch with no record the
encoder can write, an empty one included, makes no request. Each retries no response, a 5xx, 408
and 429, and drops and reports any other status. No trace context is sent. `import Traffluent`
leaves this module out; import it on its own.

The key goes in the `Authorization` header field, never in the body. It is a public client key:
Segment's and RudderStack's write keys, and Customer.io's public keys (`pk_…`), ship in their
vendors' own app and web libraries, and they let a client send data to the source and read
nothing.
Customer.io's private keys (`sk_…`) reach every Customer.io API, deleting people included, so
the factory throws ``CustomerIOSetupError/privateKey`` for one. Each factory throws for an empty
key (``SegmentSetupError``, ``RudderStackSetupError``, ``CustomerIOSetupError``), RudderStack's
for a data plane URL that isn't a plain `https` URL, and Customer.io's for a public key of the
other region.

A region has no default. Segment and Customer.io keep a workspace's data in the US or the EU, and
events posted to the other region's endpoint don't reach it, so you pick the region on purpose.

Each record becomes a track call of an anonymous user. Its `anonymousId` is the record's session,
from the sessions enricher; a record with no session is sent under its own record identifier. No
`userId`, `identify` call or traits are sent. Its `messageId` is the record's identifier, which
a redelivered record keeps, and its `timestamp` the record's timestamp in ISO 8601 with
milliseconds. The record's vendor identifier and trace context aren't sent. The standard context
goes in the spec's `context` fields (`app`, `device`, `locale`, `network` and `os`), with no
`device.id` or `advertisingId`.

Every call's `context.ip` is `0.0.0.0`, which Segment takes in place of the request's address, so
it records none. RudderStack fills in a `request_ip` from the request unless the call has one,
even beside `context.ip`, and passes it on to its destinations, so RudderStack's calls also carry
`request_ip` as `0.0.0.0`. Customer.io's references don't say whether `context.ip` takes the place
of the address it reads from an HTTP request, so it may still record the request's.

Each endpoint counts a user per `anonymousId`, so each session is one user in its reports, and so
is each record sent without a session. On a plan billed by monthly tracked users, each counts as
one. A record a store recovers after a relaunch keeps its session, so it goes out under the
`anonymousId` and `messageId` of its first send. Segment deduplicates calls by `messageId` and
drops most duplicates within about 24 hours, not all, so one it stored before the app ended is
most likely not stored again. RudderStack's and Customer.io's API references don't say whether
they deduplicate, so such a record may be stored twice there.

Properties are read through the event's schema in the `TrackingPlan` the encoder is made with. A
`Sensitive` value is never sent, whatever the record reveals. A record the encoder can't write is
left out and the rest of the batch is sent: one the plan doesn't describe, one named as one of
Customer.io's semantic events, which delete or suppress people and devices (`User Deleted`,
`User Suppressed`, `Device Deleted` and the rest), one whose event isn't `Encodable`, one holding
a value JSON can't, one whose timestamp has no ISO 8601 form, and one too large for a call. The
destination reports each as `HTTPDropReport.skipped(_:)`, a `SkippedRecord` whose reason is a
``SegmentSpecEncodingError``, and the encoder logs a notice for each semantic event name in the
plan when the destination is made.

Segment answers 200 for every request but one too large or not JSON, so a wrong region, a write
key of no source, or a batch of more calls than it takes may be answered 200 with nothing stored.
Check the source's debugger after setting the destination up. RudderStack answers a wrong write
key with 401, and Customer.io, in strict mode, with 401 too, so the destination reports those. In
strict mode Customer.io refuses a whole batch for one bad call, so the encoder leaves out each call
Customer.io documents refusing; a 400 for anything else drops the whole request.

To send to PostHog, Amplitude or Mixpanel, use `PostHogEncoding`, `AmplitudeEncoding` or
`MixpanelEncoding` instead.

```swift
import HTTPDestinations
import SegmentSpecEncoding
import TrackingPlans

let plan = try TrackingPlan()
let segment = try HTTPDestination.segment(
    writeKey: writeKey,
    region: .us,  // or .eu, where the workspace is
    plan: plan)
let tracker = Tracker(enrichers: [.sessions()])
let delivery = tracker.records.batch().deliver(to: segment)
```

The guide [Choosing Destinations](https://tyler-keith-thompson.github.io/Traffluent/documentation/traffluent/choosingdestinations)
covers what each endpoint receives, and why, in more detail.

## Topics

### Sending to Segment

- ``HTTPDestinations/HTTPDestination/segment(writeKey:region:plan:backoff:clock:)``
- ``HTTPDestinations/HTTPDestination/segment(writeKey:region:plan:transport:backoff:clock:)``
- ``SegmentRegion``
- ``SegmentSetupError``

### Sending to RudderStack

- ``HTTPDestinations/HTTPDestination/rudderStack(writeKey:dataPlane:plan:backoff:clock:)``
- ``HTTPDestinations/HTTPDestination/rudderStack(writeKey:dataPlane:plan:transport:backoff:clock:)``
- ``RudderStackSetupError``

### Sending to Customer.io Data Pipelines

- ``HTTPDestinations/HTTPDestination/customerIO(apiKey:region:plan:backoff:clock:)``
- ``HTTPDestinations/HTTPDestination/customerIO(apiKey:region:plan:transport:backoff:clock:)``
- ``CustomerIORegion``
- ``CustomerIOSetupError``

### Encoding batches

- ``SegmentSpecBatchEncoder``

### Records left out

- ``SegmentSpecEncodingError``
