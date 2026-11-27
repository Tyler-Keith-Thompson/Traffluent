# ``AptabaseEncoding``

Send records to Aptabase, in its cloud or on your own server, through its events API.

## Overview

``HTTPDestinations/HTTPDestination/aptabase(appKey:host:isDebug:plan:backoff:clock:now:)`` makes
an `HTTPDestination` (module ``/HTTPDestinations``) for Aptabase in one call. It checks your app
key and takes the region from it: an `A-EU-` key posts to `https://eu.aptabase.com/api/v0/events`,
an `A-US-` key to `https://us.aptabase.com/api/v0/events`, and a self-hosted `A-SH-` key to
`/api/v0/events` under the `host` you pass. The key goes in each request's `App-Key` header field,
and an ``AptabaseBatchEncoder`` writes the body. Each batch is split to
``AptabaseBatchEncoder/batchLimit``: 25 events a request, the most Aptabase takes, and 1,000,000
bytes a request, the encoder's own bound, under the 1 MiB that nginx takes by default in front of
many self-hosted servers. A batch with no record the encoder can write, an empty one included,
makes no request. The destination retries no response, a 5xx, 408 and 429, and drops and reports
any other status. That includes 418, which Aptabase answers when a request's body arrives slower
than 60 bytes a second after a 10-second grace period, as over a poor connection, so those records
are reported as rejected rather than retried. No trace context is sent. `import Traffluent` leaves this module out, so import
it on its own.

What Aptabase does with these events depends on more than the events themselves:

- Aptabase counts users itself. Its server hashes each request's IP address and `User-Agent`
  header field with a salt it changes every day, so a user is one network address and client on
  one day. The destination sends no user or device identifier; it can't keep the server from
  seeing the address a request comes from.
- Aptabase looks up each request's IP address and stores its country and region with every event
  in the request, so its dashboard breaks counts down by where the requests came from.
- Its sessions are the sessions enricher's. A record with no session, such as one a store
  recovered after a relaunch, counts as a session of one event.
- Its breakdowns by operating system, app version, build, device model and locale come from the
  standard context. Give the tracker the standard context enrichers, or those breakdowns are
  empty. A recovered record keeps no context, so it shows none of them.
- `isDebug` decides where events go. Aptabase shows events marked as debug events only in its
  Debug mode, apart from your users' events, and keeps them for months rather than years.
- Aptabase requires an `sdkVersion` with every event, and keeps it, but its events dashboard
  doesn't show it. The destination always sends `Traffluent`.

The app key is public, as Aptabase's own SDKs ship it inside every app, and the events API takes
no other credential, so the destination builds on every platform and an app sends to Aptabase
directly.

```swift
import AptabaseEncoding
import HTTPDestinations
import TrackingPlans

let plan = try TrackingPlan()
let aptabase = try HTTPDestination.aptabase(
    appKey: appKey,  // from the app's Instructions page: A-EU-…, A-US-… or A-SH-…
    isDebug: false,  // true for builds whose events only Debug mode should show
    plan: plan)
let tracker = Tracker(enrichers: [.sessions(), .application(), .device(), .operatingSystem(), .locale()])
let delivery = tracker.records.batch().deliver(to: aptabase)
```

For a self-hosted server, pass the URL it is reached at as `host`, such as
`https://aptabase.example.com`, with a path where it is served under one; the destination appends
`/api/v0/events`. A host must be `https`.

The factory throws ``AptabaseSetupError``: for a key that is empty or only whitespace; for one
that isn't `A-`, a region, `-` and a body of ASCII letters and digits; for a region other than
`EU`, `US`, `SH` and `DEV`, in capitals; for a self-hosted key without a host, or a cloud key with
one; and for a host that isn't a plain `https` URL, or that already ends in the endpoint. A key of
a server run in development (`A-DEV-`) is taken as a self-hosted one, so it needs the
development server's `https` URL as `host`: Aptabase's SDKs default to `http://localhost:3000`
for such a key, which the factory refuses, so serve the development server over TLS. `isDebug` has no default:
pass `true` for builds whose events only Debug mode should show, such as debug builds.

### Sessions

Each event's `sessionId` is the record's session, from the sessions enricher: its `SessionKey` as
a lowercase UUID. Nothing else identifies a record: no vendor identifier, device identifier or
account, and no trace context. A record with no session has its own identifier as its
`sessionId`: making up a session would join unrelated records, skipping the record would lose it,
and Aptabase takes no event without a session.

### What Aptabase receives

Each request is a JSON array of events. Every event has:

- `eventName`, the event's name;
- `sessionId`, the session;
- `timestamp`, the record's timestamp in ISO 8601 with milliseconds, so an event sent late still
  counts at the time it was tracked;
- `systemProps`: `osName` and `osVersion`, `appVersion` and `appBuildNumber`, `deviceModel`, and
  `locale`, the locale's language and region (`en-US`), each when the record's context has it;
  `isDebug`, as you pass it; and `sdkVersion`, `Traffluent`. A context value longer than
  Aptabase takes (30 characters of the system's name, 100 of its version, 50 of the app's
  version, 20 of its build and 100 of the device's model) is left out and the event is sent
  without it, as Aptabase would refuse the whole request. A long build number such as
  `2026.11.27.1432-abc1234` is left out of every event the build sends, so its breakdown is empty.
  The encoder logs a notice the first time it leaves out each one;
- `props`, when the event has any to send.

The record's properties are read through the event's schema in the `TrackingPlan` the encoder is
made with. Aptabase keeps strings, numbers and booleans, and only a placeholder for an object or
an array, so an object or array is flattened into dotted names: a `cart` holding `size` is
`cart.size`, and the first element of `tags` is `tags.0`. A boolean stays a boolean, which Aptabase
stores as `true` or `false`; a number keeps its JSON type; and a `nil` property is left out. A
`Sensitive` value is never sent, whatever the record reveals.

Aptabase stores a number as a .NET `decimal`, so it keeps 28 decimal places and rounds a smaller
fraction away.

### Records left out

A record the encoder can't write is left out and the rest of the batch is sent:

- one the plan doesn't describe, whose event isn't `Encodable`, or that holds a value JSON can't;
- one whose event name is only whitespace or longer than the 60 characters Aptabase takes, as
  Aptabase refuses the whole request holding one;
- one with a property, once flattened, whose name is empty, only whitespace or longer than 40
  characters, which Aptabase would drop;
- one with a string value longer than 180 characters, which Aptabase would cut short;
- one with a number of magnitude 2⁹⁶ (about 7.9 × 10²⁸) or more, past a `decimal`, for which
  Aptabase fails the whole request;
- one whose values flatten to the same name twice;
- one whose timestamp falls outside the years 1 to 9999;
- one tracked more than 23 hours before its batch is encoded, as Aptabase drops an event more than
  a day old while answering 200, the hour to spare for a queue on the server and clocks that
  disagree;
- one too large for a request of 1,000,000 bytes on its own.

Characters are counted in UTF-16, as .NET counts them, so an emoji counts two. The destination
reports each record left out as `HTTPDropReport.skipped(_:)`, a `SkippedRecord` whose reason is an
``AptabaseEncodingError``. When the destination is made, it logs a notice for each event and
property of the plan whose name would be left out.

A request is encoded once and retried as it is, so each request's deadline is 23 hours after its
oldest record was tracked: one still failing by then isn't sent again, which Aptabase would answer
with 200 while storing nothing. It is dropped and reported as
`HTTPDropReport.deadlineExceeded(deadline:recordIDs:)`. A clock that reads NaN or infinite has
every record reported. An event from the future, by a clock that runs ahead, is sent, and Aptabase
stores it at the time it arrives.

The 23 hours are measured by the device's own clock, but Aptabase measures a day by its server's.
On a device whose clock runs about a day behind, a record tracked just now carries a timestamp a
day old: the encoder sends it, and Aptabase drops it while answering 200, so the record is lost
without a report.

### What Aptabase doesn't report

Aptabase answers 200 to a request with a key of no app, of a deleted app, or of an account it has
locked, such as one past its plan's monthly events, and stores nothing: check that the first
events reach the app's Live View after setting the destination up. It doesn't remove duplicates,
so a record sent again, after a retry whose answer was lost or a store's redelivery, is counted
twice.

Aptabase takes 20 requests a second from one IP address, and answers 429 past it, which the
destination retries on its backoff.

The guide [Choosing Destinations](https://tyler-keith-thompson.github.io/Traffluent/documentation/traffluent/choosingdestinations)
covers what Aptabase receives, and why, in more detail.

## Topics

### Sending to Aptabase

- ``HTTPDestinations/HTTPDestination/aptabase(appKey:host:isDebug:plan:backoff:clock:now:)``
- ``HTTPDestinations/HTTPDestination/aptabase(appKey:host:isDebug:plan:transport:backoff:clock:now:)``
- ``AptabaseSetupError``

### Encoding batches

- ``AptabaseBatchEncoder``

### Records left out

- ``AptabaseEncodingError``
