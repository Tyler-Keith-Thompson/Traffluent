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
  which adopters miss and Bazel would have to match.
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
