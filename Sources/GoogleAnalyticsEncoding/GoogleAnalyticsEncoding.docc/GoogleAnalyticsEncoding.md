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
`import Traffluent` leaves this module out; import it on its own.

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

An app's events reach Google Analytics through a server of yours: the app sends them there, and
the server makes this destination and hands it the records. Traffluent doesn't provide that server
yet. TraffluentCollector receives an app's batches, but it doesn't forward them to Google
Analytics, and Traffluent has no decoder that turns a collector batch back into records.

Until it does, the server's job is:

1. Read each event the app sent (its name, version, identifier, timestamp, properties and session)
   and decode it into the same `@Event` type the app tracked, from a module the app and the server
   share.
2. Remake its `EventRecord` with `EventRecord(id:event:timestamp:sourceLocation:context:)`: the
   app's identifier and timestamp, and a context whose `SessionKey` is the app's session.
3. Hand each batch of records to the destination's `receive(_:)`.

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
- one tracked more than 72 hours before the batch is encoded, or more than 15 minutes after it,
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
if it happened 72 hours ago, so the encoder leaves those out too; a request retried for long after
its batch was encoded can still arrive past that window.

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
