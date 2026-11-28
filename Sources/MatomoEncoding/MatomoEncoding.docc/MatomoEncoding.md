# ``MatomoEncoding``

Send records to a Matomo installation as events, through its bulk tracking API.

## Overview

``HTTPDestinations/HTTPDestination/matomo(url:siteID:dimensions:category:plan:backoff:clock:now:)``
makes an `HTTPDestination` (module ``/HTTPDestinations``) for one site of a Matomo installation in
one call. It checks the installation's URL, the site ID, the category and the custom dimensions,
then posts bulk tracking requests to the installation's `matomo.php` with a
``MatomoBatchEncoder``. Each batch is split to ``MatomoBatchEncoder/batchLimit``: 20 records a
request, as Matomo's iOS SDK sends them, and 1,000,000 bytes a request, under the 1 MiB that
nginx takes in a body by default, as Matomo documents no limit. A batch with no record the encoder
can write, an empty one included, makes no request. The destination retries no response, a 5xx,
408 and 429, and drops and reports any other status. No trace context is sent. `import Traffluent`
leaves this module out, so import it on its own.

Matomo takes events from anyone who can reach it, so the destination needs no key, and builds on
every platform: an app sends to Matomo directly.

```swift
import HTTPDestinations
import MatomoEncoding
import TrackingPlans

let plan = try TrackingPlan()
let matomo = try HTTPDestination.matomo(
    url: url,  // where Matomo is installed: https://analytics.example.com
    siteID: 3,  // the app's site in Matomo
    dimensions: ["plan": 1],  // custom dimensions made in Matomo
    category: "Shop",  // each event's category
    plan: plan)
let tracker = Tracker(enrichers: [.sessions()])
let delivery = tracker.records.batch().deliver(to: matomo)
```

`url` is where Matomo is installed, with its path if it has one
(`https://example.com/matomo/`), not the tracker's endpoint: the destination appends `matomo.php`
itself. The factory throws ``MatomoSetupError`` for a URL that isn't `https`, has no host, holds a
user name, password, query or fragment, or already ends in a `.php` file such as `matomo.php`; for
a site ID below 1; for a category that is empty once trimmed, or longer than the 4,096 characters
Matomo stores; and for dimensions that break a rule, listed below.

### No token_auth

The destination sends no `token_auth`, and takes none. A token is a secret, and anything an app
ships can be read out of it, so a token in an app gives anyone who has the app the token's rights
over your Matomo.

Without a token, Matomo takes an event's time (`cdt`) only when it is less than a day old, and
refuses one more than a day ahead. It answers 200 to such a request all the same, and stores
nothing, so the encoder leaves out every record tracked more than 23 hours before or after it
encodes the batch, and the destination reports it, the hour to spare for a queue on the server and clocks that disagree. So a record that waits
more than 23 hours to be encoded, kept by a store through a long time offline or waiting in the
buffer behind a failing delivery, is reported as ``MatomoEncodingError/timestampOutsideWindow``
and never reaches Matomo.

A request is encoded once, and each retry sends the same bytes, so the encoder gives each request
a deadline 23 hours after its oldest record was tracked. A request still failing by then isn't
sent again, as it would reach Matomo too late to be stored: the destination drops the whole
request, its younger records too, and reports it on `dropReports` as
`HTTPDropReport.deadlineExceeded(deadline:recordIDs:)`, with every one of its records' identifiers. Only the past side of the window needs a deadline: a retry arrives later, never
earlier, so it can't carry a record further ahead of Matomo's clock than it was. The window is
measured with the device's clock, which Matomo can't see: a device whose clock is wrong by more
than a day has every record refused, without an error. A clock that reads NaN or infinite has
every record left out and reported.

To keep older records, send them to a server you run, such as a TraffluentCollector, and have
that server forward them to Matomo with a token of a user who has write access to the site,
added as `token_auth` to its bulk request's JSON. A token on a server stays secret. This module
doesn't do that.

### Visitors are sessions

Matomo counts a visitor per `_id`, 16 hexadecimal digits. The destination sends the last 64 bits
of the record's session, from the sessions enricher, in lowercase hex. Nothing else identifies a
record: no `uid`, `cid`, device identifier or account. So Matomo's visitors are sessions, and
its returning-visitor and visits-per-visitor reports say how long sessions last, not whether
people come back. That is the library's default, for privacy. Each session is one visit as long
as the sessions enricher's timeout is no longer than Matomo's visit length, 30 minutes by default
(`visit_standard_length`). With a longer timeout, a session that pauses for longer than Matomo's
visit length becomes two visits of one visitor.

A record with no session, from a tracker without the sessions enricher, is its own visitor: its
`_id` is the last 64 bits of the record's identifier. A record a store recovered after a relaunch
keeps its session, and with it the `_id` of its first send. Making up a session would join unrelated
records, and skipping the record would lose it.

Matomo recognizes a visitor by `_id` and, failing that, by a fingerprint of the request's IP
address, User-Agent, language and a daily salt, within 30 minutes. A new session's first event
has an `_id` Matomo hasn't seen, so Matomo may fold it into another visit from the same address
and User-Agent: an earlier session on the same device, or a session of another person behind the
same network. Set `trust_visitors_cookies = 1` under `[Tracker]` in Matomo's `config.ini.php` to
have Matomo match a request that has an `_id` by its `_id` alone, for every site of the
installation. When Matomo's privacy setting
to force tracking without cookies is on, Matomo ignores `_id`, and every visit is the
fingerprint's.

Matomo records the address each request comes from, as no app can override it without a token.
It masks part of the address before storing it when "Anonymize Visitors' IP addresses" is on
(Administration, Privacy, Anonymize data). In Matomo 5.14 and 6.0 it is on, masking 2 bytes, for
an installation whose administrator has never changed it, so a fresh install has it on, and an
older one keeps the setting it had. Matomo still uses the full address for geolocation and for
the fingerprint above unless "Also use the Anonymized IP addresses when enriching visits" is on
too, which is off by default. Check both settings before you send.

### What Matomo receives

Each request is a JSON object, `{"requests":[…]}`, holding one tracking request per record, oldest
first: `?` and a query string, every value percent-encoded but for letters, digits, `-`, `.`, `_`
and `~`. Each tracking request is a Matomo event:

| Parameter | Holds |
|---|---|
| `idsite` | The site ID |
| `rec`, `apiv` | `1` |
| `_id` | The session's last 64 bits, or the record's |
| `cdt` | The record's time, in whole seconds since 1970 |
| `ca` | `1`, so Matomo doesn't take the request for a page view should its Events plugin be off |
| `e_c` | The category you give, such as your app's name |
| `e_a` | The event's name |
| `lang` | The record's locale, as a BCP 47 identifier, when it has `LocaleKey` |
| `dimension<ID>` | The value of each property the dimensions map |

Matomo's Events reports group events by category, then action, then name. The category is the
argument you give, as an app's events have no grouping Matomo would show better, and the action is
the event's name, so the Event Actions report lists your events. No event name (`e_n`) or value
(`e_v`) is sent.

The User-Agent is the one `URLSession` sends, which Matomo reads for the device and operating
system. The rest of the standard context isn't sent.

### Custom dimensions

Matomo numbers each site's custom dimensions as you make them (Administration, Websites, Custom
Dimensions), so ``MatomoDimensions`` maps your plan's property names to their IDs:
`["plan": 1, "seats": 2]`. A property is mapped by name in every event that has it. Its value is
read through the event's schema in the `TrackingPlan`: a string as it is, a number as JSON writes
it, a Boolean as `true` or `false`, and an array or object as its JSON. A `nil` sends no value.
A `Sensitive` property is never sent, whatever the record reveals, so it can't be mapped.

A property no dimension is mapped to is never sent, and the record goes without it. When the
destination is made, it logs a notice for each event with such properties, once.
``MatomoDimensions/unmappedProperties(in:)`` lists them, so a test can check that every property
you mean to send has a dimension.

The factory throws for a dimension ID below 1, a property mapped twice, a property no event of the
plan has, a property that is `Sensitive` in an event, and two properties of one event mapped to
one dimension, checked in that order.

Make each dimension in Matomo with the Action scope, so each event keeps its own value. A
dimension of the Visit scope holds one value a visit, the last one sent. Matomo ignores a
dimension it has no dimension of that ID for, and stores at most 250 characters of a value.

### Records left out

A record the encoder can't write, or that Matomo would refuse or change, is left out and the rest
of the batch is sent:

- one the plan doesn't describe, whose event isn't `Encodable`, or that holds a value JSON can't;
- one whose event name is empty once Matomo removes line breaks and trims it, or longer than the
  4,096 characters Matomo stores of an action;
- one whose timestamp has no whole seconds of `Int64`, or is more than 23 hours from when the batch
  is encoded;
- one with a dimension's value longer than 250 characters;
- one whose tracking request is more than a request of 1,000,000 bytes can hold.

Lengths are counted as Matomo stores the text: without line breaks or NUL characters, trimmed of
spaces and tabs at either end, and with `&`, `<`, `>`, `"` and `'` written as the HTML entities
Matomo stores them as, so `&` counts 5. Matomo removes the line breaks and trims the spaces of a
name or value it keeps too.

The destination reports each as `HTTPDropReport.skipped(_:)`, a `SkippedRecord` whose reason is a
``MatomoEncodingError``. When the destination is made, it logs a notice for each event of the plan
whose name would be left out.

### What Matomo doesn't report

Matomo answers 200 to a bulk request it can read, whatever its tracking requests hold. One it
refuses is counted as `invalid` in the answer's JSON and not stored, and only a request with a
token learns which. When the answer says Matomo refused every one, as for a site ID of no
site, the destination drops the request and reports it as
`HTTPDropReport.rejectedInBody(status:reason:recordIDs:)`. When it tracked some and refused
others, the refused ones are lost with only a notice in the log, as the answer doesn't say which
they were. When its counts add up to fewer than the request's tracking requests, or are both 0,
Matomo skipped some without saying so, as after a database lock wait timeout, and the destination
sends the request again until its deadline; Matomo counts the ones it had tracked twice.

A server with the QueuedTracking plugin's queue turned on answers every bulk request with an
image as soon as it queues the request, before it checks any tracking request in it. The
destination counts the request as delivered. The server stores the valid tracking requests
later, and it drops the rest, such as those for a site ID of no site, without reporting them. On
such a server, check the site ID before you ship, and check that the first events show up in the
site's Visits Log.

A server set to require a token for every bulk request (`bulk_requests_require_authentication`)
refuses each one: Matomo 6.0 without the QueuedTracking queue answers 401, which the destination
drops and reports, and Matomo 5.14 answers 500, which the destination retries until the request
is cancelled. Leave that setting off.

Matomo doesn't remove duplicates. A record is sent more than once when a request is retried after
Matomo stored it but the answer was lost, when a delivery sends a cancelled batch again, and when
a store redelivers records after a relaunch, and Matomo counts each copy.

The guide [Choosing Destinations](https://tyler-keith-thompson.github.io/Traffluent/documentation/traffluent/choosingdestinations)
covers what Matomo receives, and why, in more detail.

## Topics

### Sending to Matomo

- ``HTTPDestinations/HTTPDestination/matomo(url:siteID:dimensions:category:plan:backoff:clock:now:)``
- ``HTTPDestinations/HTTPDestination/matomo(url:siteID:dimensions:category:plan:transport:backoff:clock:now:)``
- ``MatomoSetupError``

### Custom dimensions

- ``MatomoDimensions``
- ``MatomoUnmappedProperty``

### Encoding batches

- ``MatomoBatchEncoder``

### Records left out

- ``MatomoEncodingError``
