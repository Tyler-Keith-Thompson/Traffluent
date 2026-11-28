# Traffluent: triage charter

## What it is
Traffluent is a vendor-neutral analytics library for Swift. Typed events go through one pipeline
that fans them out to many destinations, and it runs on Apple platforms and Linux. It exists
because vendor SDKs are singletons with stringly typed events and `[String: Any]` bags, and the
neutral wrappers are thin and skip the hard parts. It optimizes for correctness the compiler can
check: a malformed or unconsented event should be a type error or a dropped event, never a silent
bad row in a dashboard.

## In scope
- Typed events: events are Swift values with typed properties, and the API never takes a string
  name plus an untyped property bag.
- The pipeline: stages before, enrichment, destination and after. Context enrichment (device,
  app, session, user identity), filtering, sampling and transformation.
- Multiplexing to any number of destinations behind one public destination protocol. Anyone can
  write a destination in their own package.
- The first-party destinations (D1), plus test, console or logging destinations.
- The hard parts: batching, on-disk persistence across launches, retry with backoff, flushing on
  lifecycle events, consent gating (per destination and per purpose), schema enforcement and
  versioning, and identity as pseudonymous session IDs only (D4).
- Automatic instrumentation: app lifecycle, sessions, screen views, control taps and similar events
  that need no hand-written call sites. Opt in, and each kind can be turned off (D8).
- Support on Apple platforms and Linux (not WebAssembly: D6). Platform-only behaviour (UIKit or
  SwiftUI hooks, background tasks) goes behind `#if canImport` so the rest still builds.
- Swift 6 strict concurrency from the start: no singletons and no global mutable state, but for
  the one settable-once default tracker N2 allows.
- Tooling to define or generate typed events from a schema, if the owner settles that it belongs
  here (see Open questions).
- Benchmarks, fuzzing and mutation tests of the pipeline, per AGENTS.md.

## Not in scope
- N1. Stringly typed or `[String: Any]` event APIs as the main way to track. That is the problem
  the project exists to fix. Untyped values may appear only inside a destination's encoding.
- N2. Global singletons or shared mutable instances (`Analytics.shared`). Callers create and own
  the instances they need. The owner amended N2 on 2026-11-26 (TRAF-81): "Bootstrap fallback:
  amend N2 to allow one settable-once default tracker". So `Tracker.bootstrap(_:)`, after
  swift-log's `LoggingSystem.bootstrap`, may make one tracker the process's default, which
  `Tracker.current` gives wherever no `withTracker` binding reaches (a detached task, a
  framework's callback). It is set once, never replaced or cleared: a second call throws
  `TrackerAlreadyBootstrapped` and changes nothing. The app still creates and owns that tracker,
  and the binding still wins inside its scope. Nothing else is shared that way: an item asking
  for another process-wide instance, a resettable default or a `TrackingSystem` type is still
  turned down.
- N3. Vendor lock-in in the core. No core module may import or depend on a vendor SDK, and no core
  type may be named after a vendor. Vendor code lives only in its destination module.
- N4. Wrapping every vendor in this repo. Destinations beyond D1 belong in their own packages,
  built on the public destination protocol, unless the owner adds one.
  The owner amended N4 on 2026-11-26 (TRAF-101): "We should add destinations for other popular analytics providers. File backlog tickets for a bunch of those. Let's make this as plug and play as possible." So
  destinations for popular analytics vendors now belong in this repo, under D1's rules for them;
  vendors beyond D1's list still belong in their own packages until the owner adds them.
- N5. An analytics backend, dashboard, query engine or data warehouse. Traffluent is the client
  side. Where events end up belongs to the destination's vendor. The one exception, by the
  owner's decision on 2026-11-22 (TRAF-31): a self-hosted collector in a separate package, which
  ingests Traffluent batches, validates them against the tracking plan, dedupes redelivered
  records, stores them and can forward them. On 2026-11-23 the owner extended it: the collector
  also ships analytics dashboards over what it stores, as a web UI and a mobile app. A
  general-purpose query engine and a data warehouse stay out, and none of it lives in this repo.
- N6. Crash reporting, performance tracing (APM) and general logging. Other tools do those jobs.
  A destination may forward to OpenTelemetry, but Traffluent is not a tracing SDK.
- N7. Apple-only features that break other platforms. A feature that can't work off Apple must
  compile out there, not stop the package building.
- N8. Fingerprinting or tracking that gets around the user's consent or the platform's privacy
  rules (ATT, privacy manifests). Consent gating is a feature, never something to work around.

## Rules a request must fit
- AGENTS.md's house rules: modules come from `scripts/modules.py`, warnings are errors, Swift 6
  language mode, Swift Testing, and README examples copied verbatim into tests.
- Public types are value types or actors, and all of them are `Sendable`. No `@unchecked
  Sendable` and no `nonisolated(unsafe)` without a written proof in the change.
- An event that can be invalid must fail to compile where possible, and otherwise be rejected
  at the pipeline boundary with a reason a test can observe.
- Use the owner's libraries before writing your own versions: Afluent for retry, timeout and
  shared async work; DependencyInjection for wiring and test doubles outside the library;
  SwiftPRNG for seeded sampling and tests; BenchmarkHarness for performance gates. The library's
  own modules take no DependencyInjection dependency, so adopters never need it: they take seams
  as parameters and share a tracker through a task-local (AGENTS.md, "Seams and composition").
- A new external dependency in a core module needs a reason that Foundation and the owner's
  libraries don't cover. It must build on Linux, or be Apple-only (`APPLE_ONLY_PACKAGES`).
- Persistence and retry changes need tests of crashes, relaunches and offline periods: an event
  stored must be delivered or dropped on purpose, never lost silently or sent twice unannounced.
  Before the worker stores it, a crash may lose it (D5).

## Belongs elsewhere
- Template machinery (Bazel rules, the justfile, CI, `scripts/modules.py`'s generator, the
  benchmark and fuzz setup) → github.com/Tyler-Keith-Thompson/ProjectTemplate.
- Retry, timeout, async sequencing or subject behaviour missing from Afluent → Afluent's board.
- Container or test-double gaps → DependencyInjection's board. Seeded-random gaps → SwiftPRNG's
  board.
- Destinations for vendors not in D1's list (N4) → their own packages, not this backlog, until the
  owner adds them. Those in D1's list belong here (TRAF-101).

## Kinds, labels and Ready
- bug: wrong behaviour in shipped code, especially events lost, sent twice or sent without
  consent. Lost or unconsented events come first.
- feature: new capability within In scope. docs: README, DocC or AGENTS.md.
- An item is Ready when it names the module it touches and the behaviour to observe in a test,
  and says which platforms it applies to when that isn't all of them.
- No labels are defined yet.

## Decisions
- D1. The first-party destination is `HTTPDestination` with `CollectorEncoding`, which sends
  batches to the self-hosted TraffluentCollector (N5). PostHog is a second first-party
  destination, `PostHogEncoding` over the same `HTTPDestination`, written against PostHog's HTTP
  capture API and not its SDK; it is open source and self-hostable, so neither is a lock-in, and
  plain HTTP runs on Linux too. The owner amended D1 on 2026-11-25 (TRAF-63): it had named only
  PostHog, picked at setup, while what shipped first was the collector path. Rejected: Segment
  (another pipeline, so it would duplicate this one), Firebase or Amplitude (vendor SDKs, Apple- or
  vendor-bound), and OpenTelemetry as the only destination (built for traces, not product
  analytics).
  The owner amended D1 again on 2026-11-26 (TRAF-101): "We should add destinations for other popular analytics providers. File backlog tickets for a bunch of those. Let's make this as plug and play as possible." Each
  vendor gets one `<Vendor>Encoding` module over `HTTPDestination`, written against the vendor's
  public HTTP ingestion API and never its SDK (N3, N7), each its own product and listed in
  `NON_UMBRELLA_MODULES`, so `import Traffluent` names no vendor. Each module offers one throwing
  factory on `HTTPDestination` that fills in the endpoint, encoder and limits, builds
  on `PropertyJSON`'s shared pieces, and passes `DestinationTesting`'s conformance checks. The
  vendors, after PostHog: Amplitude (TRAF-102), Mixpanel (TRAF-103), the Segment spec (Segment,
  RudderStack and Customer.io; TRAF-104), GA4's Measurement Protocol (TRAF-105, server-side only;
  see below), Snowplow (TRAF-106), TelemetryDeck (TRAF-107), Matomo (TRAF-108), Heap
  (TRAF-109) and Aptabase (TRAF-110). This reverses the rejection of Segment above: as a plain
  sink, one more destination the pipeline delivers to, it duplicates nothing. The rejection of
  Firebase's and Amplitude's SDKs stands; Amplitude's destination uses its HTTP API.
  Under the same request (TRAF-104), Segment-spec endpoints are allowed as plain-sink
  destinations: Segment, RudderStack and Customer.io Data Pipelines each receive records after
  Traffluent's own typing, consent gating and batching, from one module, `SegmentSpecEncoding`
  (not `SegmentEncoding`, which reads as an encoding of `SegmentStore`'s segments), with a
  factory per endpoint. It sends track calls only: no `identify`, traits or `userId` (D4). The
  rejection of Segment above stands only for Segment as Traffluent's pipeline itself.
  GA4 (TRAF-105, decided 2026-11-27): the Measurement Protocol takes only requests carrying the
  stream's `api_secret`, and Google's docs say not to expose it in an app, as anyone holding it can
  send events to the property. `GoogleAnalyticsEncoding` is therefore server-side only. The whole
  module (factory, encoder, region and errors) is compiled under `#if os(macOS) || os(Linux)`, so
  an app for iOS, iPadOS, tvOS, watchOS, visionOS or Mac Catalyst that uses it fails to compile.
  A Mac app (AppKit or SwiftUI) compiles the factory, as a Mac server must, but the factory
  refuses it at run time: it throws `GoogleAnalyticsSetupError.appBundle` when the main bundle is
  an `.app` or `.appex`. The docs say what shipping the secret exposes, and that the secret sits in
  every request's URL. An app's events reach GA4 through the adopter's server, which remakes each
  `EventRecord` with the app's `SessionKey` and calls the destination's `receive`; Traffluent
  doesn't provide that server yet (TraffluentCollector doesn't forward to GA4, and there is no
  collector-batch decoder). The encoder writes a web or data stream's request (`measurement_id`,
  `client_id` from the session, else the record ID) and nothing beyond the session (D4): no
  Firebase `app_instance_id`, `user_id`, user properties, IP, device or advertising ID, with ad
  consent sent as denied. Rejected: shipping the secret in apps with a warning; a factory on every
  platform that takes the secret at run time (both put a credential that writes to the property
  into a binary anyone can read); and a SwiftPM trait or `-D` define to opt in to the factory,
  which adopters miss and Bazel would have to match. A record more than 71 h before encode time
  or 15 min after it is skipped (`timestampOutsideWindow`), the hour to spare under GA4's 72 for
  the request to reach Google and clocks that disagree, and each request's
  `EncodedRequest.deadline` is its oldest record plus the same 71 h, so one retried past it is
  dropped whole, younger records too, and reported as `HTTPDropReport.deadlineExceeded` rather
  than stored misdated (TRAF-134). Rejected: re-encoding a dropped request's younger records.
  Source break for vendor destinations (TRAF-134): `HTTPDropReport` gains `deadlineExceeded`, so
  an exhaustive `switch` needs the case; the deadline-setting split is
  `requests(for:in:maximumAge:encoding:oversized:)`, which takes a `Duration` and throws
  `NegativeMaximumAge`, beside the unchanged spelling without it; and `EncodedRequest`'s equality
  now includes `deadline`.
  Snowplow (TRAF-106, decided 2026-11-27): `SnowplowEncoding` sends the tracker protocol's
  `payload_data` 1-0-4 to `<collector>/com.snowplowanalytics.snowplow/tp2`, one self-describing
  event (`e=ue`, data in `ue_pr`) per record, from every platform, as a collector needs no secret.
  Only `sid`, the session, identifies a record (D4): no `duid`, `uid`, `nuid`, `tnuid`,
  `client_session` entity, IDFV or IDFA. Every request carries `SP-Anonymous: *`, so the collector
  sets no `sp` cookie (which `URLSession` would keep across sessions) and records no IP. Each
  event's schema is `iglu:<vendor>/<name>/jsonschema/<version>-0-0`, and the plan exports an Iglu
  registry (`TrackingPlan.writeIgluRegistry(to:vendor:registry:)`, the plugin's `--iglu-vendor`
  and `--iglu-registry`). An event version is a SchemaVer MODEL. The export compares an event with
  its newest published `N-0-k` through the plan's own compatibility check, on decoded documents: a
  breaking difference throws `breakingChange`, and a compatible one is the next ADDITION,
  superseding the earlier ones, for Iglu Server alone; for a static repository, which ignores
  `$supersedes`, it throws `additionNeedsNewVersion`. The registry kind has no default. Published
  files are never changed or deleted. Rejected: a warning instead of the static-repository throw
  (events would fail silently), and naming the exact `N-0-k` in the encoder (an installed release
  would then never pick up a later addition). Batching keeps the trackers' 25 events and 40,000
  bytes, and an event up to 150,000 bytes goes in a request of its own, as the trackers send one,
  under SQS's 192 kB (`BatchLimit.sendsLargeRecordsAlone`, off for every other encoder). Rejected: patching
  `N-0-0` in place (Snowplow treats published schemas as immutable), `1-0-(N-1)` for version N (a
  Traffluent version is a breaking change), base64 `ue_px`/`cx` (a third larger, and its URL
  safety matters only to GET), and sending `stm` (a retry keeps the first attempt's, shifting
  `derived_tstamp`). The collector answers 200 before validation, so the docs say that an event
  failing validation is lost to the warehouse though delivered.
  TelemetryDeck (TRAF-107, decided 2026-11-27): `TelemetryDeckEncoding` sends Ingest API v3, a
  JSON array of flat signals posted to `https://nom.telemetrydeck.com/v3/<namespace>/`, from every
  platform, as the app ID is public (TelemetryDeck's SDKs ship it in every app). Rejected: v2,
  which TelemetryDeck no longer extends and which stringifies values. `clientUser` is SHA-256 of
  the lowercase session, in lowercase hex, as the SDKs hash a user identifier with their default,
  empty salt, computed with swift-crypto `1.0.0..<6.0.0` (CryptoKit on Apple platforms, BoringSSL
  on Linux; every major from 1 builds under Swift 6.4, so servers capped below 5 still resolve;
  CommonCrypto is Apple-only, and a hand-written SHA-256 is rejected). No `salt:` is taken:
  `sessionID` sends the same UUID in the clear, so a salt hides nothing, and the server salts and
  hashes `clientUser` again. Rejected: keeping a salt documented as doing nothing (unused API). `sessionID` is the
  session, and nothing else identifies a record (D4), so TelemetryDeck's user counts are session
  counts; the docs say so, and that an adopter who wants devices puts `VendorIdentifierKey` in the
  context and sends through a destination that reads it, or writes their own enricher and encoder.
  A record with no session is hashed by its own ID and sent with no `sessionID`. Rejected: a made-up
  session (joins unrelated records) and skipping the record. `testMode:` is required. Rejected: a
  `#if DEBUG` default in the library (it would be the library's build, not the app's) and a
  default of `false` (debug builds would pollute production counts). Properties keep their JSON
  type, flattened with `.` (TelemetryDeck doesn't index nested values), with `nil` left out. A name
  outside ASCII `[A-Za-z0-9._-]` makes TelemetryDeck refuse the whole request with 422, so the
  record is skipped; so is an event or parameter name in the `TelemetryDeck.` scope, in any case,
  which v3 reserves for the SDKs and the server, and a parameter named exactly as one of v3's
  event members (`appID`, `clientUser`, `receivedAt`, `type`, `sessionID`, `isTestMode`,
  `floatValue`), which it would replace in the flat event. v3 doesn't rename or clean keys and
  rejects no other name, so the SwiftSDK's list of reserved v2 keys (`platform`, `count` and the
  rest) is not refused. Rejected: renaming such keys (two names could collide, and the dashboard
  would show names the plan doesn't have). A timestamp outside the years 1 to 9999, which the
  server can't parse, is skipped. Batching is 100 signals a request (the SwiftSDK's) and
  1,000,000 bytes a request (the encoder's own bound; TelemetryDeck documents none), with 333,333
  bytes a signal, a third of v3's 1,000,000, leaving room for the escapes a re-encoder commonly
  adds. No `floatValue` is sent. The server answers 200 for any namespace and app
  ID and doesn't deduplicate, so the docs say a typo loses everything silently and a resent record
  counts twice.
  Matomo (TRAF-108, decided 2026-11-27): `MatomoEncoding` posts bulk tracking requests,
  `{"requests":["?…",…]}`, to `matomo.php` under the installation's `https` base URL, from every
  platform, over HTTP alone (N3), with no `token_auth` anywhere: a token in an app is anyone's.
  The factory takes the base URL and appends `matomo.php`, refusing any URL whose last component
  ends in `.php`. Rejected: taking the endpoint (`piwik.php`, `index.php` and proxies make it
  ambiguous) and `http`. Each record is an event: `e_c` is a required `category:` (such as the
  app's name) and `e_a` the event's name; no `e_n` or `e_v`. Rejected for `e_c`: the consent
  category (nearly always one value), the bundle ID (recovered records lack it), the event type's
  module (changes on a refactor); rejected: the event name as `e_c` under a fixed action, and
  `e_n` from a property or the version. `_id` is the session's last 64 bits in lowercase hex, or
  the record ID's when there is no session; no `uid`, `cid` or device ID (D4). Rejected: the
  first 64 bits (a v7 UUID's timestamp), a hash (no gain over random bits), `cid` (it would stop
  Matomo's config_id fingerprint from merging a new session into another visit, but forces an
  identifier D4 rules out), `new_visit` (a fingerprint match carries the old visitor over). The
  docs name `trust_visitors_cookies = 1`, cookieless mode ignoring `_id`, and IP enrichment.
  Properties reach Matomo only as numbered custom dimensions through `MatomoDimensions`
  (property name to ID, mapped in every event that has it); setup throws for an ID below 1, a
  property mapped twice, one no event has, one that is `Sensitive` in an event (read from its
  type through `WrittenType`, as the JSON Schema export marks one; never sent, so a mapping of it
  is a mistake), and two of one event on one dimension, in that order. A literal
  keeps duplicates so the factory throws instead of trapping (D10). An unmapped property is left
  out and reported once, as a setup log notice and `unmappedProperties(in:)` for tests. Rejected:
  a SkippedRecord (it would drop the record and repeat each batch). A value is a string as it is,
  anything else minified JSON, `nil` never sent. Without a token Matomo refuses a `cdt` a day old
  or a day ahead yet answers 200, so a record more than 23 hours from encode time is skipped
  (`timestampOutsideWindow`), the hour to spare for a queue on the server and clocks that disagree, and every record is when the
  clock reads NaN or infinite (D10). Rejected: leaving a broken clock to Matomo, which drops them
  unreported. Each request's `EncodedRequest.deadline` is its oldest record plus the same 23 h,
  so one retried that long is dropped whole, younger records too, and reported as
  `HTTPDropReport.deadlineExceeded` rather than answered 200 and lost (TRAF-134); only the past
  bound, as a retry only arrives later.
  `cdt` is whole Unix seconds rounded down. Also skipped: an event name empty once trimmed or
  over the 4,096 characters `log_action.name` stores, and a dimension value over the 250 Matomo
  keeps, both counted as Matomo stores them (line breaks and NULs removed, the five HTML
  entities, PHP's trim), so nothing is silently cut. Batching is 20 requests (Matomo's iOS SDK's)
  and 1,000,000 bytes (under nginx's 1 MiB default; Matomo documents none). `lang` comes from
  `LocaleKey`; no `rand`, `send_image`, `ua` or `res`. Matomo answers 200 to invalid requests and
  doesn't deduplicate, so the docs say a wrong site ID loses everything silently and a resent
  record counts twice; older records need a relay of the adopter's with a token, which the library
  doesn't provide. With `bulk_requests_require_authentication` on, Matomo 6.0 answers 400
  (dropped, reported) and 5.14 answers 500 (retried until cancelled), so the docs say to leave it
  off.
  Heap (TRAF-109, decided 2026-11-27): `HeapEncoding` posts Heap's server-side bulk track
  request, `{"app_id":…,"events":[…]}`, to `https://heapanalytics.com/api/track`, or
  `https://c.eu.heap-api.com/api/track` for the EU data center (`HeapRegion`, no default), from
  every platform. The track API's OpenAPI definition has no security scheme and needs only the
  environment's `app_id`, which Heap's SDKs ship in every app; only the user deletion API takes an
  API key, which the module never accepts (developers.heap.io/reference/track-1, /bulk-track,
  /server-side-apis-overview and /user-deletion, read 2026-11-27). Contentsquare, which owns Heap,
  documents no newer server-side ingestion. The app ID must be ASCII digits (environment IDs are
  numbers), trimmed first. Each record is an event: `event` the event's name, `identity` the
  session as a lowercase UUID (the record ID when sessionless), `idempotency_key` the record ID,
  `timestamp` ISO 8601 with milliseconds; no `user_id` (a Heap SDK's numeric ID), `session_id`
  (an SDK session, which server-side events can't link to) or standard context (Heap keeps no
  built-in property of a server-side event, so it would mix into the event's own properties).
  Heap makes and keeps a user per identity, so its users are sessions (D4), and the docs say so.
  Properties are flattened with `.`, as the siblings do, booleans sent as `"true"`/`"false"`
  (the reference lists numbers and strings only) and `nil` left out. Rejected: sending arrays for
  Heap to join with `||` (it cuts the joined string at 1,024 characters silently, and an array
  of objects has no such form). Skipped, as Heap answers 400 to a bad request and documents
  nothing of what it does past its limits: an event name over 1,024 characters, a property named
  exactly `user_id`, `session_id` or `screen_name`, a flattened name or string value of 1,024
  characters or more (UTF-16 units, JavaScript's count; rejected: bytes, which refuse ordinary
  non-Latin text far sooner), values that flatten to one name, and a timestamp outside years 1 to
  9999. Heap documents no timestamp window, so requests have no deadline and no record is skipped
  for its age. Batching is 1,000 events (Bulk Track's maximum) and 1,000,000 bytes a request (the
  encoder's own bound; Heap documents none). The docs say that server-side events don't join Heap's
  SDK sessions, that Heap shows a user of only server-side events with them hidden, and to confirm
  events appear in charts after setup, as the docs don't say what Heap answers to an unknown app ID.
  Review follow-up (2026-11-27): the server-side API complements Heap's SDKs and "you can only send
  events to identified users" (developers.heap.io/reference/server-side-apis-overview); a user with
  only server-side events shows "events are hidden" (help.heap.io article 37271959816465), its
  events aren't sessionized, so the Sessions list stays empty (37271954812049), and user-property
  session filters see only SDK sessions (37271885557265). Every user this destination makes is
  such a user, so the landing article's Overview and ChoosingDestinations' row and section say so
  first, and tell adopters to confirm events in charts, not only in the Live data feed. Still no
  standard context as properties (rejected: flattening app and device fields into each event's
  properties, which Heap has no built-in keys for and which would collide with adopters' names).
  The 15,000 events a minute per app_id is shared by every device (about 21.6M a day at a steady
  rate); Heap doesn't say whether it answers 429 (retried on the backoff, no jitter, no
  `Retry-After`, so a backlog can grow) or 400 (the whole request dropped as rejected), and the
  docs describe both. A session's own backlog of over 1,000 events passes the per-identity limit;
  kept 1,000 events a request (rejected: smaller batches, which don't pace requests).
  Deduplication holds within one identity, so a record recovered after a relaunch, sent under its
  record ID, may be stored twice, as for Amplitude (TRAF-122).
  Aptabase (TRAF-110, decided 2026-11-27): `AptabaseEncoding` posts a JSON array of events to
  `/api/v0/events` with the app key in `App-Key`, from every platform: the key is public (the
  SDKs ship it, and the server's own comment says anyone can send any key). Sources, read
  2026-11-27: the server at github.com/aptabase/aptabase 89d36185 (EventsController,
  EventBody, ResolveAppKeyAttribute, DailyUserHasher, EnvSettings, AppsController, Program.cs)
  and the Swift SDK at github.com/aptabase/aptabase-swift a1ee53e9. The server's code is the
  authority where its wiki (How-to-build-your-own-SDK) disagrees: the wiki says a session ID must
  be epoch seconds and 8 digits, the code takes any string of up to 36 characters that isn't a
  number. The key is `A-<region>-<body>`; `EU` and `US` map to `eu.aptabase.com` and
  `us.aptabase.com` and refuse a host (rejected: allowing one, which would send a cloud key
  elsewhere), `SH` and `DEV` need an `https` host (rejected: http, which would send the key in
  the clear; a server run in development takes one only behind TLS). Region case-sensitive and
  the body ASCII letters and digits, as the SDK and the server make keys; trimmed first. API
  shape: `host: URL? = nil` (rejected: a host enum, a factory per key kind). `isDebug` has no
  default, like TelemetryDeck's `testMode`. Each record: `eventName`, `sessionId` the session as
  a lowercase UUID (36 characters, the record ID when sessionless, D4; rejected: the SDK's numeric
  form, which the server checks against a 7-day window and a record ID can't fill), `timestamp`
  ISO 8601 with milliseconds, `systemProps` from the standard context (OS name and version, app
  version and build, device model, locale as `lang-REGION` or the language alone, to fit 10)
  plus `isDebug` and `sdkVersion` `"Traffluent"`, and `props` flattened with `.`. Aptabase hashes
  IP and User-Agent daily for users, so no identifier is sent and the User-Agent is left as the
  transport sets it. Booleans stay JSON booleans (the server stores them as "true"/"false", as
  the SDKs send them). Skipped, since each would fail the whole request or be dropped while
  answering 200: an event name blank or over 60, a property name blank or over 40, a string value
  over 180 (rejected: letting Aptabase cut it to 177 and "..."), a number of magnitude 2^96 or
  more (the server's decimal read throws, 500, retried forever), a flattened-name collision, a
  timestamp outside years 1 to 9999, and a record more
  than 23 hours old (the server drops one over a day old with 200; the hour covers queueing and
  clock skew), with each request's deadline 23 hours after its oldest record. A future timestamp
  is sent, as the server clamps it to arrival. Batching is 25 events (the server's maximum) and
  1,000,000 bytes (under nginx's default 1 MiB in front of self-hosted servers). A wrong, deleted
  or locked key is answered 200 with nothing stored, and there is no deduplication, so the docs
  say to check Live View and that redelivery counts twice.
  Review follow-up (2026-11-27): a system property over its model limit (osName 30, osVersion
  100, appVersion 50, appBuildNumber 20, deviceModel 100) is left out of the event, which is
  sent, with a notice logged once per member per encoder (rejected: skipping the record, as the
  standard context is the install's, so a CFBundleVersion such as 2026.11.27.1432-abc1234 would
  skip every event of the build). The server's members are all optional. The docs also say that
  Aptabase answers 418 when a body arrives under 60 bytes a second after a 10-second grace
  (src/Program.cs MinRequestBodyDataRate, ExceptionMiddleware), which HTTPDestination drops as
  rejected; that Aptabase geolocates each request's IP and stores country and region per event;
  that a device clock about a day behind loses events silently; and that `A-DEV-` keys need an
  https development server, as the SDKs' default http://localhost:3000 is refused.
- D2. Destinations are plain sinks: they receive events that have already been typed, enriched
  and consent-checked. A request to put enrichment or consent logic inside one destination is
  turned down in favour of a pipeline stage. The owner amended D2 on 2026-11-26 (TRAF-81):
  "all your current enrichment, destinations, etc require the tracker to propagate correctly.
  But a detached task will not get the tracker I set up at the app level. swift log solves this
  by letting me control metadata both at the logger level, but also where I multiplex to. I
  think you need to do the same with enrichment and such." So enrichment may also be applied at
  the fan-out, as a destination modifier, `enriched(by:)`, which runs an `Enricher` on the
  records one destination receives, the way `redactingSensitiveValues()` transforms them. The
  destination itself stays a plain sink: the modifier wraps it, and an enricher written into a
  destination's own `receive` is still turned down. Consent logic inside a destination is still
  turned down too: consent is decided before the fan-out, and `accepting(_:)` only narrows it.
- D3. Consent is both per purpose and per destination (TRAF-7, the owner's answer of
  2026-11-22). Each event type has a consent category (a purpose); each destination accepts a set
  of categories. Per category, consent is undecided, granted or denied. While it is undecided,
  events are held in memory, bounded, dropping the oldest with a drop report, and never written
  to disk. On grant, held events are delivered in order. On deny, they are dropped and reported.
  Rejected: dropping until granted, which loses first-launch events, and deciding per category.
- D4. Traffluent identifies people only by pseudonymous session IDs (the owner, 2026-11-23).
  A session ID is random, never derived from the device, the user or another ID, never persisted
  past its session, and replaced when a new session starts. Traffluent ships no "sticky"
  identifier of its own: no persisted anonymous or device ID and no alias that links sessions
  together. The one exception the owner allowed (2026-11-23): the platform's
  `identifierForVendor`, which the OS owns, scopes to the vendor's apps and resets when they are
  all removed. Traffluent may offer it as an opt-in enricher where the platform has it, never
  stored by Traffluent and never a fallback to a generated ID.
  Adopters who want one write their own Enricher and own that decision, including its consent.
  Amended 2026-11-27 (TRAF-122, the agent's default while the owner's answer is pending): a store
  may write a record's session ID into that record's own stored bytes, and only there, so a record
  recovered after a relaunch reaches vendors under the ID it was first sent with; it is deleted
  when the store deletes the record's bytes (a SegmentStore: once its whole segment is
  delivered), and no session ID is stored apart from its records.
  An item asking Traffluent to persist or link identifiers across sessions is turned down,
  pointing at the Enricher route.
- D5. Tracking accepts and nothing more (the owner, 2026-11-23): "collection can happen on any
  thread but all our work is off the main thread. Nothing expensive, no serialization, nothing
  but accepting events." `track`, `grant` and `deny` take the time, the call site and the current
  context, enqueue them and return. Enrichment, consent, encoding, persistence and delivery run
  on a worker the tracker owns, never on the caller's thread or the main actor. The structure
  enforces this: no public API runs adopter or library code on the caller. A record is durable
  once the worker has stored it; `finish()` drains first. What a crash takes before then is the
  documented loss window. Items that move work back onto the caller are turned down.
- D6. WebAssembly is not a supported platform (the owner, 2026-11-22, TRAF-14). Swift on
  wasm32-wasi runs on one thread, and its executor blocks that thread for every sleep, so
  time-based batching, the default, misfires: a probe that expected batches [0, 1, 2] at about
  1 s got [0, 1] at 8 s. The WASI test run, the WebAssembly example and every `os(WASI)` branch
  went with it, and the template's `wasm` option is off in `.template.json`. Rejected: keeping
  Wasm with count-only batching (the default would differ by platform, and a timer-free tracker
  still couldn't flush on time). It comes back when the wasm32-unknown-wasip1-threads SDK ships
  in a stable Swift release, or when an adopter asks for browser support, where JavaScriptKit's
  `JavaScriptEventLoop` or `WebWorkerTaskExecutor`, installed by the adopter's app, makes timers
  work. Re-adding starts with a probe of time batching under that real executor, before any
  build or test machinery returns. Until then an item asking for Wasm is turned down, pointing
  here.

- D7. Swift types are the source of an event's schema (TRAF-15, decided by the agent working it,
  2026-11-23; the owner asked for "codegen where it makes sense" and may change this). `@Event`
  (module EventMacros, outside the umbrella) derives the conformance, the name, an `EventSchema`
  value and the `Codable` conformance from the declaration. A schema file such as a JSON Schema
  tracking plan is an export of those types, never the input. `Codable` is allowed when the format
  is CBOR (the owner, 2026-11-26, TRAF-83: "We can use codable if it's using CBOR"), so stores
  write events through their `Codable` conformances and ship no coder of their own. Rejected: an
  external schema file with codegen into Swift, which makes the Swift type a generated copy of
  something else; a hand-written binary coder protocol (the owner, TRAF-83: "Let's do that so we
  stop shipping our own custom codable"); and a runtime Mirror walk (slow, can't see optionality).
- D8. Automatic instrumentation covers app lifecycle (TRAF-24), screen views (TRAF-22) and control
  taps (TRAF-23), and is
  opt in: nothing is tracked until the app turns it on for a scene or window, and each kind can be
  turned off (owner, 2026-11-23, on TRAF-23: "In scope, opt in"). It never swizzles, never keeps
  process-wide state (N2) and uses no Apple private API, so a kind that can only be reached that way
  is left out: SwiftUI taps (no public signal identifies a SwiftUI Button) and macOS SwiftUI
  NavigationStack pushes. Controls are named by accessibility identifier, never by label or text
  (N8), and an unnamed control is skipped rather than reported as an unidentified row.
- D9. Persisted events and records are CBOR (RFC 8949) maps keyed by property name (TRAF-35, the
  owner's choice of CBOR over a custom JSON encoder, 2026-11-23), so a stored record survives an
  added optional property or a removed one; a record that no longer decodes is dropped with a drop
  report. Stores write them through `Codable` with brokenhandsio's swift-cbor (TRAF-83, D7). New
  code keeps the 2× budget: within 2× the simulated instructions of the hand-written form it
  replaces. The record coder alone has a one-time exception (the owner, 2026-11-26, TRAF-83:
  "Don't raise, make a one time exception."). `@Event` encode and decode together must keep pace
  with a hand-written `Codable` conformance through the same package (a BASELINE in the EventMacros
  benchmarks), not with the positional form, which stays as the floor. The Persistence benchmarks'
  positional BASELINEs are a floor for the store's append and recovery, without a ratio budget.
  Simulated instructions, p50, release, at TRAF-83:

  | Benchmark | Hand-written coder | swift-cbor | Positional floor |
  |---|---|---|---|
  | `@Event` encode + decode | 2,365K (1.30×) | 26,487K (14.6×) | 1,813K |
  | Hand-written `Codable` encode + decode | — | 26,487K (14.6×) | 1,813K |
  | SegmentStore append | 4,979K (1.22×) | 58,889K (14.5×) | 4,072K |
  | SegmentStore recovery | about 10M (1.7×) | 63,143K (10.6×) | 5,959K |

  Why: a coder of the project's own is code to own, fuzz and keep in step with Codable, and the
  owner wanted none shipped. The cost is the package's `Codable` path, which builds a CBOR value
  tree and allocates for it; `@Event`'s generated code matches a hand-written conformance's count
  exactly, so nothing is left to win on Traffluent's side. A store writes once per tracked event,
  off the caller's path, so the time is spent where a delay costs nothing. A faster CBOR `Codable`
  package, or a release of this one that streams, is taken without a new decision. Rejected:
  raising the 2× budget for everything (it keeps holding new code to the hand-written form);
  forking swift-cbor to make it faster (a coder of our own by another name); the positional
  encoding (breaks on any field change); SwiftCBOR (an allocation per item, and its own value type
  rather than `Codable`).
- D10. Throw, don't trap (the owner, 2026-11-26, TRAF-86): "Trap/checked only makes sense for high
  performance libs where fatalError is a reasonable thing to do. An analytics library doesn't make
  sense. `checked` should be removed and EVERYTHING that can throw, should throw. No trapping."
  Every precondition on an argument is a typed throw on the plain spelling, one error type per
  invariant; there are no `checked:` spellings. A limit reached inside the pipeline drops the
  record with a drop report. Library code has no force unwrap, `as!` or `try!`. No stream the
  library hands out traps on a second reader (TRAF-97, TRAF-99). An item that adds a trap or a
  `checked:` spelling is turned down, pointing here.

## Open questions
- Should Android or Windows (Swift SDKs exist) join Apple platforms and Linux? Each needs its
  own persistence and networking.
- Do deep links and network requests also get automatic instrumentation (D8 covers screen views
  and taps)?
- Should there be adapters or a migration path from Segment's analytics-swift or vendor SDKs?
- Is server-side Swift (Vapor services sending analytics) a target user, or only apps?
- Are the template's minimum OS versions (macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2)
  right for a library that apps adopt, or should they go lower?
- Which vendors, if any, beyond D1 should get first-party destinations here (N4)? Answered on
  2026-11-26 (TRAF-101): Amplitude (TRAF-102), Mixpanel (TRAF-103), the Segment spec (Segment,
  RudderStack, Customer.io; TRAF-104), GA4 Measurement Protocol (TRAF-105, server-side only),
  Snowplow (TRAF-106), TelemetryDeck (TRAF-107), Matomo (TRAF-108), Heap (TRAF-109) and
  Aptabase (TRAF-110). See D1.
