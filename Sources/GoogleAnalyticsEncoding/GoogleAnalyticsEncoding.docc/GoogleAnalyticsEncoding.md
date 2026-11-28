# ``GoogleAnalyticsEncoding``

Send records from a server to a Google Analytics 4 web or data stream through the Measurement Protocol.

## Overview

``HTTPDestinations/HTTPDestination/googleAnalytics(measurementID:apiSecret:region:plan:backoff:clock:now:)``
makes an `HTTPDestination` (module ``/HTTPDestinations``) for a Google Analytics 4 stream in one
call. It checks the measurement ID and the API secret, and posts to the Measurement Protocol's
`/mp/collect` endpoint of the region (``GoogleAnalyticsRegion``) with a
``GoogleAnalyticsBatchEncoder``. It splits each batch to the Measurement Protocol's limits
(``GoogleAnalyticsBatchEncoder/batchLimit``): 25 events and 100 KB a request. A batch with no
record the encoder can write, an empty one included, makes no request. The destination retries no
response, a 5xx, 408 and 429, and drops and reports any other status. No trace context is sent.
`import Traffluent` leaves this module out; import it on its own. An app doesn't use it:
its events reach Google Analytics through TraffluentCollector (Getting an app's events to Google
Analytics, below).

### The API secret stays on a server

The Measurement Protocol takes only requests that carry one of the stream's API secrets, and
anyone holding that secret can send events to the property. Google's docs say not to expose it in
an app, and an app's binary can be read by anyone who installs it.

So the whole module is compiled for macOS and Linux alone, where a server runs. An app for iOS,
iPadOS, tvOS, watchOS, visionOS or Mac Catalyst that calls the factory, or names the encoder, fails
to compile. A Mac app, AppKit or SwiftUI, compiles the factory as a Mac server does, but the
factory refuses it at run time: it throws ``GoogleAnalyticsSetupError/appBundle`` when the
process's main bundle is an `.app` or an `.appex`. Nothing stops a Mac app from building an
`HTTPDestination` with this encoder and an endpoint it writes itself, secret and all, so don't.

The secret is also in the query of every request's URL. Don't log the destination, its requests or
a transport's URLs.

The factory throws ``GoogleAnalyticsSetupError`` for an empty measurement ID, for one that isn't
`G-` followed by uppercase letters and digits, and for an empty API secret. The region has no
default: `.global` is Google's default endpoint, and `.eu` has Google collect the data in the EU.

### Getting an app's events to Google Analytics

An app's events reach Google Analytics through TraffluentCollector, which forwards the records it
accepts to a Google Analytics 4 web stream over the Measurement Protocol. The app holds no Google
secret and doesn't link this module. It sends to the collector as any source does: an
`HTTPDestination` with a `CollectorBatchEncoder` (module `CollectorEncoding`) and the
collector's API key. Its tracker's sessions enricher gives each record the session that the
collector sends as its `client_id`. In the app, in Swift:

```swift
import TrackingPlans
import Traffluent

let plan = try TrackingPlan()
let collector = HTTPDestination(
    endpoint: collectorURL,  // https://collector.example.com/v1/batches
    headerFields: [.authorization: "Bearer \(apiKey)"],  // the collector's API key, not Google's
    encoder: CollectorBatchEncoder(plan: plan))
// The sessions enricher gives each record the session the collector sends as its client_id.
let tracker = Tracker(enrichers: [.sessions()])
let delivery = tracker.records.batch().deliver(to: collector)
```

The measurement ID, the API secret and the region are set in the collector's environment, not in
Swift and not in the app:

```sh
SERVER_GA4_MEASUREMENT_ID=G-ABC123                 # the web stream's measurement ID
SERVER_GA4_API_SECRET=replace-with-the-api-secret  # one of that stream's Measurement Protocol API secrets
SERVER_GA4_REGION=global                           # or eu; global when unset
SERVER_TRACKING_PLAN=/srv/tracking-plan            # the exported plan, required to forward
```

Set the measurement ID and the API secret together; with neither set, nothing is forwarded. A
variable set empty counts as unset. The collector refuses to start, in development as in
production, when only some are set, when the region is neither `global` nor `eu`, or when it has
no tracking plan, which it needs because the plan marks which properties are sensitive. Its
`GET /v1/admin/forwarding` route, and the Forwarding screens of its web UI and iOS app, report the
measurement ID and the region, how many records are pending, forwarded and skipped, and the last
failure. No route answers the API secret.

The collector writes the same Measurement Protocol requests as this module's encoder: one
client's events a request, at most 25 events and 100,000 bytes. The `client_id` is the record's
session as two decimal halves, or the record's identifier when it has no session. Each event has
a `session_id` from a version 7 session's start and a `timestamp_micros`, and ad consent is denied.
Its parameters are the properties with every property the plan marks sensitive, at the version
the record states, left out, objects and arrays flattened into names joined by `_`, and nulls left
out. No `user_id`, user properties,
location or device is sent, and no other context value. It skips the same records this module's
encoder does (reserved or malformed names, more than 25 parameters, a string over 100 bytes), and
a record more than 72 hours older or 15 minutes newer than the moment the collector encodes it.
The collector logs each skipped record and counts it in the status. The app's `dropReports` don't
hear of it, since the collector accepted the record.

The collector checks each record against its plan at the version the record states, and rejects
one at a version the plan doesn't hold. It reads a record with no version, from an app built with
an earlier Traffluent, at version 1, or at the plan's lowest version of its event when the plan
has no version 1, as `CollectorBatchDecoder` does.

Only records the plan accepted, and that the collector stored for the first time, are queued to
forward, in the same statement that stores them. So a rejected record is never forwarded, and
neither are the records of a batch the app sends again, which the collector holds already. Records it
stored while forwarding wasn't configured aren't forwarded later. A service drains the queue: it
claims up to 100 records for 60 seconds, so collectors sharing a database never send one record
at the same time, posts them, and settles the ones Google Analytics took. A record whose post
failed, or whose collector stopped, is sent again once its claim lapses, so one Google stored
before the answer was lost is counted twice. The Measurement Protocol answers 2xx with a wrong
measurement ID or API secret too, so a record sent counts as forwarded whatever Google made of
it: check the property's Realtime report after setting the variables.

### Sending from a server of your own

To send from a server of yours instead, such as a relay in front of Google Analytics, make this
destination there and hand it the records. The app sends to the relay as it would to the
collector, with an `HTTPDestination` and a `CollectorBatchEncoder`. The relay reads each body back
into records with a `CollectorBatchDecoder` (module `CollectorEncoding`), made with the same
`TrackingPlan` and the same `@Event` types: the app's events, from a module the app and the server
share, plus the earlier versions the relay declares (below). It hands the records to the
destination:

```swift
import CollectorEncoding
import GoogleAnalyticsEncoding
import HTTPDestinations
import TrackingPlans

let plan = try TrackingPlan()
let decoder = try CollectorBatchDecoder(plan: plan)
let googleAnalytics = try HTTPDestination.googleAnalytics(
    measurementID: measurementID,  // the web or data stream's, G-…
    apiSecret: apiSecret,  // from the server's configuration, never an app's
    region: .global,  // or .eu, to have Google collect the data in the EU
    plan: plan)

// For each request the relay receives: its body, as the app's CollectorBatchEncoder wrote it.
let batch = try decoder.batch(from: body)
await googleAnalytics.receive(batch.records)
```

Each record keeps the identifier, timestamp and event the app sent, and the app's `SessionKey` in
its context, so Google Analytics gets each session as its own `client_id`. A record the decoder
can't read, such as one of an event the server has no type of, is left out and reported in
`batch.undecodedRecords`; the batch's other records are still sent. A body that isn't a collector
batch at all throws `NotACollectorBatch`, which the relay can answer with a 400.

Each record states its event's version, and the decoder reads it into the relay's type of that
name and version. Once an app raises an event's version, the releases still installed keep sending
the earlier one, so the relay keeps a type for each version the apps send. Two `@Event` types of
one name fail to build unless the earlier one sits in a `private` or `fileprivate` scope.
`TrackingPlan()` and the decoder still find it there:

```swift
@Event(name: "order_placed", version: 2)
struct OrderPlaced {
    var items: Int
    var currency: String
}

// Version 1, which releases still installed send.
private enum EarlierVersions {
    @Event(name: "order_placed")
    struct OrderPlaced {
        var items: Int
    }
}
```

Declare the earlier version's type at file scope, as above, or `fileprivate` inside another type:
`@Event` can't expand inside a type that is a `private` member of another
([Defining Events](https://tyler-keith-thompson.github.io/Traffluent/documentation/traffluent/definingevents)).

A record at a version the relay has no type for is left out and reported as `unknownVersion`; the
rest of its batch is still sent. Apps built with an earlier Traffluent send no version, and the
decoder reads such a record at version 1, or at the relay's lowest version when it has no
version 1. Those apps sent version 1 unless the event declared another. A record one of them sent
at a raised version is read at version 1 too: it is reported as `undecodableProperty` when its
properties don't fit that type, and is read as version 1 when they fit.

Don't track the events again through a `Tracker` with `.sessions()` on the server. That tracker
would give every event the server's own session, so every user of the app would arrive in Google
Analytics as one `client_id`.

A server that tracks its own events, rather than an app's, uses a tracker as any app does:

```swift
import HTTPDestinations
import GoogleAnalyticsEncoding
import TrackingPlans

let plan = try TrackingPlan()
let googleAnalytics = try HTTPDestination.googleAnalytics(
    measurementID: measurementID,  // the web or data stream's, G-…
    apiSecret: apiSecret,  // from the server's configuration, never an app's
    region: .global,  // or .eu, to have Google collect the data in the EU
    plan: plan)
// A server tracking its own events: its sessions are the server's.
let tracker = Tracker(enrichers: [.sessions()])
let delivery = tracker.records.batch().deliver(to: googleAnalytics)
```

The rest of this article describes this module's destination.

### What Google Analytics receives

Each request holds one client's events, as the Measurement Protocol takes one `client_id` a
request. The `client_id` is the record's session, from the sessions enricher, written as the two
halves of its UUID in decimal, joined by a period, the form the Measurement Protocol asks for. A
record with no session is sent under its own record identifier, in a request of its own. Each
event's `session_id` parameter is the session's start in Unix milliseconds, so Google Analytics
groups the session's events, and its `timestamp_micros` is the record's timestamp. Every request
sends ad consent as denied, so Google uses none of the events for advertising.

No `user_id`, user properties, location, IP address, device or user agent is sent, and no
advertising identifier. The record's vendor identifier, trace context and standard context aren't
sent either. Google Analytics counts a user per `client_id`, so each session is one user in its
reports, and so is each record sent without a session.

No `engagement_time_msec` is sent, as Traffluent doesn't measure engagement. Without it the events
don't count toward engagement time or engaged sessions, and the Realtime and Users reports can show
no users while events arrive. Check the event counts, not the user counts, to see that the
destination works.

Properties are read through the event's schema in the `TrackingPlan` the encoder is made with,
and become the event's `params`. A `Sensitive` value is never sent, whatever the record reveals.
Google Analytics takes only strings, numbers and booleans, so a nested value is spread into a
parameter for each value it holds, named after its path joined by `_` (`cart_size`, `tags_0`), and
a `null` is left out.

### Records sent twice

The Measurement Protocol has no field that identifies an event, so Google Analytics can't tell a
repeat from a new event, and counts every one it receives. A record is sent more than once when a
request is retried after Google stored it but the answer was lost, when a delivery sends a
cancelled batch again, and when a store redelivers records after a relaunch. Each such record is
counted twice in Google Analytics.

### Records left out

A record the encoder can't write is left out and the rest of the batch is sent:

- one the plan doesn't describe, whose event isn't `Encodable`, or that holds a value JSON can't;
- one whose event name, or a parameter's name, is longer than 40 bytes, doesn't start with a
  letter, or holds anything but letters, numbers and `_`;
- one whose event name Google Analytics keeps (`session_start`, `first_visit`, `error` and the rest
  of its reserved names), or takes only from an app stream (`screen_view`, `ad_impression`,
  `in_app_purchase`);
- one with a parameter Google Analytics keeps (a `firebase_`, `ga_` or `google_` prefix) or named
  `session_id`, which the encoder writes;
- one of more than 25 parameters, counting `session_id`, or with a string longer than 100 bytes;
- one tracked more than 71 hours before the batch is encoded, or more than 15 minutes after it,
  and one whose timestamp has no microseconds form;
- one too large for a request.

Google Analytics wouldn't refuse such an event: it answers 2xx either way. Under its default,
relaxed validation it stores the event without the parameter that breaks a rule, or under a name
it never checked, so the report would hold an event other than the one tracked. The encoder leaves
the record out and reports it instead. A Google Analytics 360 property takes values of up to 500
characters, but the encoder holds every property to the standard 100 bytes.

The destination reports each as `HTTPDropReport.skipped(_:)`, a `SkippedRecord` whose reason is a
``GoogleAnalyticsEncodingError``. The encoder logs a notice for each event and property of the plan
named as Google Analytics refuses when the destination is made; rename such an event or property,
raising the event's version, to send it.

### What the Measurement Protocol doesn't report

The Measurement Protocol answers 2xx to every request it receives, including one it can't read and
one whose events it doesn't store. A wrong measurement ID or API secret is answered 2xx with nothing
stored, so check the property's Realtime event counts after setting the destination up. Google's
validation server, `/debug/mp/collect`, checks a body's shape but not the measurement ID or the API
secret, so a body it accepts can still be stored nowhere. A record older than 72 hours is stored as
if it happened 72 hours ago, so the encoder leaves out one older than 71 hours, the hour to spare
for the request to reach Google and clocks that disagree. A request is encoded once and retried as
it is, so the encoder gives each request a deadline 71 hours after its oldest record was tracked. A
request still failing by then isn't sent again: the destination drops the whole request, its
younger records too, and reports it on `dropReports` as
`HTTPDropReport.deadlineExceeded(deadline:recordIDs:)`, with every one of its records' identifiers.

To send to PostHog, Amplitude, Mixpanel or Segment, use `PostHogEncoding`, `AmplitudeEncoding`,
`MixpanelEncoding` or `SegmentSpecEncoding` instead.

The guide [Choosing Destinations](https://tyler-keith-thompson.github.io/Traffluent/documentation/traffluent/choosingdestinations)
covers what Google Analytics receives, and why, in more detail.

## Topics

### Sending to Google Analytics

- ``HTTPDestinations/HTTPDestination/googleAnalytics(measurementID:apiSecret:region:plan:backoff:clock:now:)``
- ``HTTPDestinations/HTTPDestination/googleAnalytics(measurementID:apiSecret:region:plan:transport:backoff:clock:now:)``
- ``GoogleAnalyticsRegion``
- ``GoogleAnalyticsSetupError``

### Encoding batches

- ``GoogleAnalyticsBatchEncoder``

### Records left out

- ``GoogleAnalyticsEncodingError``
