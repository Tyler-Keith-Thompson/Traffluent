# Traffluent: triage charter

## What it is
Traffluent is a vendor-neutral analytics library for Swift. Typed events go through one pipeline
that fans them out to many destinations, and it runs on every platform Swift does. It exists
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
  versioning, and identity (anonymous ids, identify, alias, reset).
- Automatic instrumentation: app lifecycle, sessions, screen views and similar events that need
  no hand-written call sites. Each kind can be turned off.
- Support on every platform: Apple platforms, Linux and Wasm. Platform-only behaviour (UIKit or
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
  side. Where events end up belongs to the destination's vendor.
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
  libraries don't cover. It must build on Linux and Wasm, or be Apple-only (`APPLE_ONLY_PACKAGES`).
- Persistence and retry changes need tests of crashes, relaunches and offline periods: an event
  accepted once must be delivered or dropped on purpose, never lost silently or sent twice
  unannounced.

## Belongs elsewhere
- Template machinery (Bazel rules, the justfile, CI, `scripts/modules.py`'s generator, the
  benchmark, fuzz and Wasm setup) → github.com/Tyler-Keith-Thompson/ProjectTemplate.
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
  plain HTTP runs on Linux and Wasm. Rejected: Segment (another pipeline, so it would duplicate
  this one), Firebase or Amplitude (vendor SDKs, Apple- or vendor-bound), and OpenTelemetry as
  the only destination (built for traces, not product analytics). The owner said "provider of
  your choice", so this was picked at setup and the owner may change it.
- D2. Destinations are plain sinks: they receive events that have already been typed, enriched
  and consent-checked. A request to put enrichment or consent logic inside one destination is
  turned down in favour of a pipeline stage.

## Open questions
- What does "all platforms" cover: Android and Windows (Swift SDKs exist), Embedded Swift, or
  Wasm in the browser and WASI? Each needs its own persistence and networking.
- Where does the event schema come from: Swift types first (macros, or protocols with derived
  encoding), or an external schema file (JSON Schema, a tracking plan) with codegen? Should
  codegen tooling live in this repo?
- How much automatic instrumentation: lifecycle and sessions only, or also screen views
  (UIKit or SwiftUI), taps, deep links and network requests? Opt in or opt out?
- What is the consent model: per destination, per purpose (GDPR-style categories), or both? What
  happens to events queued before consent is given: hold them, drop them, or decide per purpose?
- Should there be adapters or a migration path from Segment's analytics-swift or vendor SDKs?
- Is server-side Swift (Vapor services sending analytics) a target user, or only apps?
- Are the template's minimum OS versions (macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2)
  right for a library that apps adopt, or should they go lower?
- Which vendors, if any, beyond D1 should get first-party destinations here (N4)?
