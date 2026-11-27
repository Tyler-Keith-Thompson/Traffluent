# ``TelemetryDeckEncoding``

Send records to TelemetryDeck as signals, through its Ingest API v3.

## Overview

``HTTPDestinations/HTTPDestination/telemetryDeck(appID:namespace:testMode:plan:backoff:clock:)``
makes an `HTTPDestination` (module ``/HTTPDestinations``) for TelemetryDeck in one call. It checks
the app ID and your organization's namespace, then posts to
`https://nom.telemetrydeck.com/v3/<namespace>/` with a ``TelemetryDeckBatchEncoder``. Each batch is
split to ``TelemetryDeckBatchEncoder/batchLimit``: 100 signals a request, as TelemetryDeck's
SwiftSDK sends them; 333,333 bytes a signal, a third of Ingest API v3's limit of 1,000,000; and
1,000,000 bytes a request, the encoder's own bound, as TelemetryDeck documents none. A batch with no record the encoder can write, an empty one included, makes
no request. The destination retries no response, a 5xx (TelemetryDeck answers 503 while its queue
is full), 408 and 429, and drops and reports any other status. No trace context is sent.
`import Traffluent` leaves this module out, so import it on its own.

The app ID only says which app a signal belongs to, and TelemetryDeck's own SDKs ship it inside
every app, so the destination builds on every platform and an app sends to TelemetryDeck directly.

```swift
import HTTPDestinations
import TelemetryDeckEncoding
import TrackingPlans

let plan = try TrackingPlan()
let telemetryDeck = try HTTPDestination.telemetryDeck(
    appID: appID,  // from the app's settings in the TelemetryDeck dashboard
    namespace: "com.example",  // your organization's namespace
    testMode: false,  // true for builds whose signals only Test Mode should show
    plan: plan)
let tracker = Tracker(enrichers: [.sessions()])
let delivery = tracker.records.batch().deliver(to: telemetryDeck)
```

The factory throws ``TelemetryDeckSetupError`` for an app ID that is empty or only whitespace,
and for a namespace TelemetryDeck doesn't take. A namespace holds only ASCII letters, digits, `.`,
`_` and `-`, and can't be `w`, `.` or `..`.

`testMode` has no default. TelemetryDeck shows test signals only in its Test Mode, apart from your
real users, and its SDK picks test mode for debug builds. Pass whatever your app uses to tell its
builds apart, such as `true` under `#if DEBUG` and `false` otherwise.

### User counts are sessions

TelemetryDeck counts users by `clientUser`. The destination sends the record's session, from the
sessions enricher, as `clientUser`, hashed the way TelemetryDeck's SDKs hash a user identifier:
SHA-256 of the lowercase UUID, in lowercase hex, with the SDKs' default, empty salt.
TelemetryDeck salts and hashes `clientUser` again on its server. The same session is also the
`sessionID`, in the clear, so a salt of the app's own would hide nothing, and the destination takes
none. Nothing else identifies a record: no vendor identifier, device identifier or
account, and no trace context.

So TelemetryDeck's user counts are session counts. A person who opens the app three times is three
users, and its retention charts show how long a session lasts, not whether people come back. That
is the library's default, for privacy. To count devices instead, put
`StandardContext`'s `VendorIdentifierKey` in the records' context and send them through a
destination that reads it, or write your own enricher and encoder that send the identifier you
choose. This encoder sends the session alone.

A record with no session, such as one a store recovered after a relaunch, is its own user: its
`clientUser` is the hash of the record's identifier, and it has no `sessionID`. Making up a session
would join unrelated records, and skipping the record would lose it.

### What TelemetryDeck receives

Each request is a JSON array of signals, one per record. Every signal has:

- `appID`, as given, without surrounding whitespace;
- `type`, the event's name;
- `clientUser`, the hashed session, and `sessionID`, the session;
- `receivedAt`, the record's timestamp in ISO 8601 with milliseconds, so a signal sent late still
  counts at the time it was tracked;
- `isTestMode`, `"true"` or `"false"`;
- `TelemetryDeck.SDK.name`, `Traffluent`.

The record's properties are read through the event's schema in the `TrackingPlan` the encoder is
made with, and sit beside these, each keeping its JSON type. TelemetryDeck doesn't index nested
values, so an object or array is flattened into dotted names: a `cart` holding `size` is
`cart.size`, and the first element of `tags` is `tags.0`. A `nil` property is left out. A
`Sensitive` value is never sent, whatever the record reveals. No `floatValue` is sent.

The standard context, when the record has it, becomes TelemetryDeck's built-in parameters:

| Context | Parameters |
|---|---|
| `ApplicationKey` | `TelemetryDeck.AppInfo.version`, `.buildNumber` and `.versionAndBuildNumber` |
| `DeviceKey` | `TelemetryDeck.Device.modelName` |
| `OperatingSystemKey` | `TelemetryDeck.Device.operatingSystem`, `.platform`, `.systemVersion`, `.systemMajorVersion` and `.systemMajorMinorVersion` |
| `LocaleKey` | `TelemetryDeck.RunContext.locale` and `.language`, and `TelemetryDeck.UserPreference.region` |

The bundle identifier, the form factor and the network aren't sent.

### Records left out

A record the encoder can't write is left out and the rest of the batch is sent:

- one the plan doesn't describe, whose event isn't `Encodable`, or that holds a value JSON can't;
- one whose event name or parameter name, once flattened, holds anything but ASCII letters, digits,
  `.`, `_` and `-`, or is empty. TelemetryDeck refuses the whole request for one such name.
- one whose event name or parameter name starts with `TelemetryDeck.`, in any case: TelemetryDeck
  reserves that scope for its SDKs' parameters and its server's;
- one with a parameter named as one of a signal's own members, `appID`, `clientUser`,
  `receivedAt`, `type`, `sessionID`, `isTestMode` or `floatValue`, spelled exactly so: in the flat
  signal it would replace the member. A name like one in another case, such as `Type`, is sent.
- one whose values flatten to the same name twice;
- one whose timestamp falls outside the years 1 to 9999, which TelemetryDeck can't parse;
- one whose JSON is over 333,333 bytes. TelemetryDeck refuses the whole request for a signal over
  1,000,000 bytes as its server writes it, which may be larger than the encoder's; a third leaves
  room for the escapes a re-encoder commonly adds.

The destination reports each as `HTTPDropReport.skipped(_:)`, a `SkippedRecord` whose reason is a
``TelemetryDeckEncodingError``. When the destination is made, it logs a notice for each event and
property of the plan whose name would be left out.

### What TelemetryDeck doesn't report

TelemetryDeck answers 200 to any namespace and any app ID it can read, so a typo in either loses
every signal without an error. Check that the first signals show up in the dashboard, in Test Mode
when `testMode` is `true`.

TelemetryDeck doesn't remove duplicates. A record is sent more than once when a request is retried
after TelemetryDeck stored it but the answer was lost, when a delivery sends a cancelled batch
again, and when a store redelivers records after a relaunch, and TelemetryDeck counts each copy.

The guide [Choosing Destinations](https://tyler-keith-thompson.github.io/Traffluent/documentation/traffluent/choosingdestinations)
covers what TelemetryDeck receives, and why, in more detail.

## Topics

### Sending to TelemetryDeck

- ``HTTPDestinations/HTTPDestination/telemetryDeck(appID:namespace:testMode:plan:backoff:clock:)``
- ``HTTPDestinations/HTTPDestination/telemetryDeck(appID:namespace:testMode:plan:transport:backoff:clock:)``
- ``TelemetryDeckSetupError``

### Encoding batches

- ``TelemetryDeckBatchEncoder``

### Records left out

- ``TelemetryDeckEncodingError``
