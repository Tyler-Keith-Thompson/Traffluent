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
- One first-party destination (D1), plus test, console or logging destinations.
- The hard parts: batching, on-disk persistence across launches, retry with backoff, flushing on
  lifecycle events, consent gating (per destination and per purpose), schema enforcement and
  versioning, and identity as pseudonymous session IDs only (D4).
- Automatic instrumentation: app lifecycle, sessions, screen views, control taps and similar events
  that need no hand-written call sites. Opt in, and each kind can be turned off (D8).
- Support on Apple platforms and Linux (not WebAssembly: D6). Platform-only behaviour (UIKit or
  SwiftUI hooks, background tasks) goes behind `#if canImport` so the rest still builds.
- Swift 6 strict concurrency from the start: no singletons and no global mutable state.
- Tooling to define or generate typed events from a schema, if the owner settles that it belongs
  here (see Open questions).
- Benchmarks, fuzzing and mutation tests of the pipeline, per AGENTS.md.

## Not in scope
- N1. Stringly typed or `[String: Any]` event APIs as the main way to track. That is the problem
  the project exists to fix. Untyped values may appear only inside a destination's encoding.
- N2. Global singletons or shared mutable instances (`Analytics.shared`). Callers create and own
  the instances they need.
- N3. Vendor lock-in in the core. No core module may import or depend on a vendor SDK, and no core
  type may be named after a vendor. Vendor code lives only in its destination module.
- N4. Wrapping every vendor in this repo. Destinations beyond D1 belong in their own packages,
  built on the public destination protocol, unless the owner adds one.
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
  accepted once must be delivered or dropped on purpose, never lost silently or sent twice
  unannounced Once
  stored, that is; before the worker stores it, a crash may lose it (D5).

## Belongs elsewhere
- Template machinery (Bazel rules, the justfile, CI, `scripts/modules.py`'s generator, the
  benchmark and fuzz setup) → github.com/Tyler-Keith-Thompson/ProjectTemplate.
- Retry, timeout, async sequencing or subject behaviour missing from Afluent → Afluent's board.
- Container or test-double gaps → DependencyInjection's board. Seeded-random gaps → SwiftPRNG's
  board.
- Destinations for other vendors (N4) → their own packages, not this backlog.

## Kinds, labels and Ready
- bug: wrong behaviour in shipped code, especially events lost, sent twice or sent without
  consent. Lost or unconsented events come first.
- feature: new capability within In scope. docs: README, DocC or AGENTS.md.
- An item is Ready when it names the module it touches and the behaviour to observe in a test,
  and says which platforms it applies to when that isn't all of them.
- No labels are defined yet.

## Decisions
- D1. The first-party destination is PostHog, written against its HTTP capture API and not its
  SDK. It is open source and self-hostable, so even the default destination isn't a lock-in, and
  plain HTTP runs on Linux too. Rejected: Segment (another pipeline, so it would duplicate
  this one), Firebase or Amplitude (vendor SDKs, Apple- or vendor-bound), and OpenTelemetry as
  the only destination (built for traces, not product analytics). The owner said "provider of
  your choice", so this was picked at setup and the owner may change it.
- D2. Destinations are plain sinks: they receive events that have already been typed, enriched
  and consent-checked. A request to put enrichment or consent logic inside one destination is
  turned down in favour of a pipeline stage.
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
  value and the binary encoding from the declaration. A schema file such as a JSON Schema tracking
  plan is an export of those types, never the input. Rejected: an external schema file with
  codegen into Swift, which makes the Swift type a generated copy of something else; `Codable`
  (too slow, per the owner); and a runtime Mirror walk (slow, can't see optionality).
- D8. Automatic instrumentation covers app lifecycle (TRAF-24), screen views (TRAF-22) and control
  taps (TRAF-23), and is
  opt in: nothing is tracked until the app turns it on for a scene or window, and each kind can be
  turned off (owner, 2026-11-23, on TRAF-23: "In scope, opt in"). It never swizzles, never keeps
  process-wide state (N2) and uses no Apple private API, so a kind that can only be reached that way
  is left out: SwiftUI taps (no public signal identifies a SwiftUI Button) and macOS SwiftUI
  NavigationStack pushes. Controls are named by accessibility identifier, never by label or text
  (N8), and an unnamed control is skipped rather than reported as an unidentified row.

## Open questions
- Should Android or Windows (Swift SDKs exist) join Apple platforms and Linux? Each needs its
  own persistence and networking.
- Do deep links and network requests also get automatic instrumentation (D8 covers screen views
  and taps)?
- Should there be adapters or a migration path from Segment's analytics-swift or vendor SDKs?
- Is server-side Swift (Vapor services sending analytics) a target user, or only apps?
- Are the template's minimum OS versions (macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2)
  right for a library that apps adopt, or should they go lower?
- Which vendors, if any, beyond D1 should get first-party destinations here (N4)?
