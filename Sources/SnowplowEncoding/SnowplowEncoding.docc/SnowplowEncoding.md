# ``SnowplowEncoding``

Send records to a Snowplow collector as self-describing events, whose schemas come from the tracking plan.

## Overview

``HTTPDestinations/HTTPDestination/snowplow(collector:vendor:appID:plan:backoff:clock:)`` makes an
`HTTPDestination` (module ``/HTTPDestinations``) for a Snowplow pipeline in one call. It checks the
collector's URL, the Iglu vendor and the app ID, and posts to the collector's
`/com.snowplowanalytics.snowplow/tp2` endpoint with a ``SnowplowBatchEncoder``. It splits each
batch to the limits of Snowplow's own mobile trackers (``SnowplowBatchEncoder/batchLimit``): 25
events and 40,000 bytes a request, with a larger event, of up to 150,000 bytes, in a request of
its own. A batch with no record the encoder can write, an empty one
included, makes no request. The destination retries no response, a 5xx, 408 and 429, and drops
and reports any other status. No trace context is sent. `import Traffluent` leaves this module out;
import it on its own.

A collector takes events from anyone who can reach it, so there is no key or secret, and the
destination builds on every platform: an app sends to the collector directly.

```swift
import HTTPDestinations
import SnowplowEncoding
import TrackingPlans

let plan = try TrackingPlan()
let snowplow = try HTTPDestination.snowplow(
    collector: collector,  // https://collector.example.com
    vendor: "com.example",  // the Iglu vendor the plan is exported under
    appID: "shop-ios",
    plan: plan)
let tracker = Tracker(enrichers: [.sessions()])
let delivery = tracker.records.batch().deliver(to: snowplow)
```

The factory throws ``SnowplowSetupError`` for a collector URL that isn't `https`, that has no host,
a user name, a query or a fragment, or that already ends in the endpoint; for a vendor Iglu
doesn't take; and for an empty app ID or one longer than 255 UTF-16 code units.

### Schemas from the tracking plan

Each event is a self-describing event: its data comes with the Iglu URI of the schema it must
match, and Snowplow's pipeline validates it against that schema before loading it. The URI is
named after the event and its version, under the vendor the destination is given:

```
iglu:<vendor>/<name>/jsonschema/<version>-0-0
```

Version N of an event is SchemaVer `N-0-0`, and events always name it. Raising an event's version
is a breaking change, which is SchemaVer's MODEL. The export compares each event with the newest
schema of its version the registry holds, by what the two mean rather than their bytes, as the
plan's own check does:

- An event that hasn't changed keeps its published file, and nothing is written.
- A breaking change at the same version, such as a property made required, is refused: raise the
  event's version.
- A compatible change, such as an optional property added, is an ADDITION. For Iglu Server the
  export writes it as `N-0-1`, then `N-0-2`, each listing the earlier ones in `$supersedes`, and
  Snowplow validates events naming `N-0-0` against the newest, so a release already in users'
  hands keeps validating. Superseding needs Iglu Server 0.11.0 or later and Enrich 3.8.0 or later.
  A static repository doesn't support it: it would validate those events against `N-0-0` alone,
  so for one the export refuses the change, and the event needs a new version.

Write the registry from the plan with `TrackingPlan.writeIgluRegistry(to:vendor:registry:)`, the
`iglu <vendor> server|static <registry-directory>` command of the tracking plan's executable, or
the `export-tracking-plan` plugin's `--iglu-vendor` and `--iglu-registry`. Then publish it with
`igluctl` before the release that sends the events.

An event name Iglu takes holds only ASCII letters, digits, `-` and `_`, and the version must be 1
or more. The encoder skips every record of an event that breaks either rule, and logs a notice for
each such event of the plan when the destination is made. The export refuses such an event too.

### What Snowplow receives

Each request is a `payload_data` 1-0-4 array of events, one per record. Every event has:

- `e`, `ue`: a self-describing event, with its data in `ue_pr` as JSON text;
- `eid`, the record's identifier, which a redelivered record keeps;
- `dtm` and `ttm`, the record's timestamp in milliseconds, so Snowplow's `derived_tstamp` is when
  the event was tracked;
- `aid`, the app ID; `p`, the platform; `tv`, `traffluent`; and `ip`, `0.0.0.0`.

No `stm` is sent: a retried request sends the same body again, so a sent time would be the first
attempt's, and Snowplow would move the event later by however long the retries took.

The standard context, when the record has it, goes in `co` as Snowplow's `mobile_context` 1-0-3
(the operating system, Apple as the manufacturer, the device model, the network type and the
language) and `application` 1-0-0 (the app's version and build). The platform is `mob` for a phone,
pad, watch or Vision Pro, `tv` for an Apple TV, `pc` for a Mac and `app` for a record with no device.

Properties are read through the event's schema in the `TrackingPlan` the encoder is made with. A
`Sensitive` value is never sent, whatever the record reveals.

### Only the session identifies a record

The record's session, from the sessions enricher, is its `sid`, Snowplow's `domain_sessionid`, and
nothing else identifies it. No `duid`, `uid`, `nuid` or `tnuid` is sent, no `client_session`
entity (its `userId` lasts across sessions), and no IDFV, IDFA or other device identifier. The
record's vendor identifier and trace context aren't sent either. A record with no session, such as
one a store recovered after a relaunch, is sent without a `sid`. Snowplow's mobile data models
read a session from the `client_session` entity, so set the unified package's
`snowplow__session_identifiers` to `[{"schema": "atomic", "field": "domain_sessionid"}]` for these
events.

The collector would give each device an identifier of its own: it sets an `sp` cookie, which
`URLSession` keeps and sends back, and records the request's IP address. Every request carries
`SP-Anonymous: *`, so the collector sets and reads no cookie, records `network_userid` as all
zeros, and records no IP address or forwarding header fields.

### Records left out

A record the encoder can't write is left out and the rest of the batch is sent:

- one the plan doesn't describe, whose event isn't `Encodable`, or that holds a value JSON can't;
- one whose event name Iglu doesn't take, or whose version is below 1;
- one whose timestamp falls outside the years 0 to 9999, which Snowplow's enrichment fails;
- one whose JSON is over 150,000 bytes, which the smallest of a pipeline's streams, SQS's 192 kB,
  might not take with the request around it.

The destination reports each as `HTTPDropReport.skipped(_:)`, a `SkippedRecord` whose reason is a
``SnowplowEncodingError``.

### What the collector doesn't report

The collector answers 200 to every request it can read and validates nothing. Snowplow checks the
events later, in enrichment. An event whose data its schema rejects, whose schema the pipeline's
Iglu resolver can't find, or that is larger than the pipeline's stream takes, becomes a failed
event: it is kept apart and never reaches the warehouse, though the destination counted it as
delivered. Publish each schema before the release that sends it, and watch the pipeline's failed
events after a change to the plan. Snowplow's resolver caches schemas, for 10 minutes by default,
so a schema published after the first event that names it can still be missed for that long.

Snowplow doesn't remove duplicates as events arrive. A record is sent more than once when a request
is retried after the collector stored it but the answer was lost, when a delivery sends a cancelled
batch again, and when a store redelivers records after a relaunch. Each copy keeps its `eid`, so
Snowplow's data models, which deduplicate on `event_id`, count it once.

The guide [Choosing Destinations](https://tyler-keith-thompson.github.io/Traffluent/documentation/traffluent/choosingdestinations)
covers what Snowplow receives, and why, in more detail.

## Topics

### Sending to Snowplow

- ``HTTPDestinations/HTTPDestination/snowplow(collector:vendor:appID:plan:backoff:clock:)``
- ``HTTPDestinations/HTTPDestination/snowplow(collector:vendor:appID:plan:transport:backoff:clock:)``
- ``SnowplowSetupError``

### Encoding batches

- ``SnowplowBatchEncoder``

### Records left out

- ``SnowplowEncodingError``
