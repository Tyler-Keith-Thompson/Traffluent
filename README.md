# Traffluent

Traffluent is an analytics library for Swift that isn't tied to a vendor. Events are strongly
typed values, not stringly typed names with `[String: Any]` property bags. A tracker records
them, and one delivery fans each batch of them out to as many destinations as you like. It also handles what thin wrappers skip:
batching, on-disk persistence, retry, consent gating, schema enforcement and automatic
instrumentation. It is built for Swift 6 strict concurrency, has no singletons, and runs on Apple
platforms and Linux. Use it in place of the in-house typed event layer most
large apps end up writing, with vendor SDKs as plain sinks.

[Documentation](https://tyler-keith-thompson.github.io/Traffluent/documentation/)

## Installation

Traffluent requires Swift 6.4 and supports macOS 15, iOS 18, tvOS 18, watchOS 11 and visionOS 2
or later, and Linux.

```swift
dependencies: [
    .package(url: "https://github.com/Tyler-Keith-Thompson/Traffluent", from: "0.0.1"),
],
```

Then add a product to your target, either the umbrella or individual modules:

```swift
.target(name: "MyApp", dependencies: [
    .product(name: "Traffluent", package: "Traffluent"),
    // or, for example:
    // .product(name: "Trackers", package: "Traffluent"),
]),
```

## Usage

Every example here is a test in `Tests/TraffluentTests`, so it cannot drift from the code.

```swift
import Traffluent

struct SignedUp: Event {
    var plan: String
}

let tracker = Tracker()
let delivery = tracker.records.batch().deliver(to: ConsoleDestination())
tracker.track(SignedUp(plan: "pro"))
await tracker.finish()
try await delivery.execute()  // prints: SignedUp SignedUp(plan: "pro")
```

`track` returns at once, from any thread, the main thread included: it only reads the clock,
captures the call site and the task's `ServiceContext`, and queues them. A worker the tracker
owns, never on the main actor, does the rest in the order events were tracked, so no enricher,
consent check, encoding or disk write runs on the caller. It records the event as an
`EventRecord`, with the time it was tracked and the caller's file, module, function, line and
column, and adds the record to the tracker's `records`, an `AsyncSequence`. Delivering is a chain of operators over it:
`batch()` gathers the records into batches of 20, or every 30 seconds while any are waiting, and
`deliver(to:)` hands each batch to every destination. The chain is lazy, an Afluent unit of
work: nothing runs until `execute()`. Run it for as long as the app tracks events; `finish()`
waits for the worker to catch up, then ends the records, so the delivery sends what is still
pending and completes. Records tracked
before the delivery starts, or between two, wait for it, so none is lost.

Batching is Afluent's `batch(strategy:)`, so any of its strategies, or one of your own, chooses
when a batch goes out:

```swift
let delivery = tracker.records
    .batch(strategy: .either(.count(50), .time(interval: .seconds(10), clock: ContinuousClock())))
    .deliver(to: ConsoleDestination(), batchBufferLimit: 10)
```

`batch(clock:)` takes the clock the default's 30 seconds run on, and `Tracker(now:)` the
wall-clock time records are stamped with, the system's unless you pass another (a test clock and
fixed dates in tests). Each destination receives its batches in order from a buffer of its own,
`batchBufferLimit` batches deep (100 by default), so a slow one holds up only itself; when its
buffer is full, its oldest waiting batch is dropped. A delivery that finished or failed can be
executed again (a retry). Cancelling one is permanent, as for every Afluent unit of work, so after
a cancellation build a new delivery; it delivers every record the cancelled one hadn't read.

Code deep in an app needn't be handed the tracker. Bind it to a task with `withTracker` and read
it anywhere inside with `Tracker.current`:

```swift
let tracker = Tracker()
withTracker(tracker) {
    Tracker.current.track(SignedUp(plan: "pro"))
}
await tracker.finish()
try await tracker.records.batch().deliver(to: ConsoleDestination()).execute()  // prints: SignedUp SignedUp(plan: "pro")
```

The binding reaches child tasks, and a nested `withTracker` replaces it for its own scope. It
doesn't reach callbacks a framework runs on tasks of its own, such as SwiftUI button actions: pass
those a `Tracker`. With no tracker bound, `Tracker.current` drops each event and logs it at debug
level.

Every record also carries the `ServiceContext` it was tracked in (swift-distributed-tracing's
`Instrumentation` module), read through typed keys, so a destination can see the session, the
screen or the active span's trace without a string-keyed bag. `Enricher`s add to it as each event
is tracked:

```swift
import Instrumentation

enum ScreenKey: ServiceContextKey {
    typealias Value = String
}

let screen = Enricher { context in
    context[ScreenKey.self] = "Checkout"
}
let tracker = Tracker(enrichers: [screen])
tracker.track(SignedUp(plan: "pro"))  // its record's context[ScreenKey.self] is "Checkout"
```

To see events beside your logs or traces, deliver to `LoggerDestination(logger:)` (module
`LoggingDestinations`) or `SpanEventDestination(tracer:)` (module `TracingDestinations`). Each is a
module of its own, so only apps that use swift-log or swift-distributed-tracing that way link it.
A span event joins the span active when the event was tracked, even if delivery runs later.

To send batches to a server, deliver to `HTTPDestination(endpoint:headerFields:encoder:)` (module
`HTTPDestinations`). It posts each batch as one request whose body is what your `BatchEncoder`
writes for it, so events need no `Codable` conformance and the wire format is yours. A failed send
is logged and dropped, without holding up the other destinations. It sends with `URLSession` by
default, or through any `HTTPTransport` you pass as `transport:`. The bootstrapped tracing
instrument, or the one you pass as `instrument:`, injects the trace context of the batch's first
record into the request's header fields, so a server that extracts it joins the request to the
app's trace; the encoder's `Content-Type` always wins, and with no instrument bootstrapped no
header is added. Only the first record's context travels in the header fields; write each
record's into the body if the server needs it.

To test what your code tracks, deliver its tracker's records to an `InMemoryDestination` (module
`DestinationTesting`; it depends on no test framework) and read it after the delivery:
`events(of: SignedUp.self)`, `records` or `batches`.

### Consent

Each event type names the purpose it is collected for, its `consentCategory`: `.analytics` unless
it says otherwise. Give the tracker a `Consent`, which the app updates as the user decides, and an
event reaches a destination only once its category is granted:

```swift
struct AdClicked: Event {
    static let consentCategory = ConsentCategory.advertising
    var campaign: String
}

let consent = Consent([.analytics: .granted])
let tracker = Tracker(consent: consent)
let delivery = tracker.records.batch().deliver(
    to: ConsoleDestination(),
    ConsoleDestination().accepting(.advertising)
)
tracker.track(SignedUp(plan: "pro"))          // delivered: analytics is granted
tracker.track(AdClicked(campaign: "spring"))  // held: advertising is undecided
consent.grant(.advertising)                   // delivers the held AdClicked
```

A category is undecided until the app grants or denies it. While undecided, its events are held in
memory, not written to a store, up to `heldRecordLimit` records (1,000 by default) across every
category, the oldest dropped first when the hold is full. Granting delivers them in the order they
were tracked, before anything tracked after the grant; denying drops them. `grant` and `deny`
return at once: they record the decision, and the tracker's worker releases or drops what it
held. Events tracked while their category is denied are never collected. Every drop of a record
that was held or kept is reported on `consent.dropReports`, as a `ConsentDropReport`, as it
happens, so none is lost silently; held records are lost if the app ends first. Records a store
recovered from an earlier run are gated again as the tracker starts: they are held outside the
bound, as the store still keeps them, and a store forgets each one that is denied. A tracker given
no consent delivers every event.

A destination receives every category the consent lets through, unless `accepting(_:)` narrows it
to the categories it serves, as the second destination above takes only advertising.

### Sensitive values and call sites

A property destinations shouldn't see unless they must is a `Sensitive` value. A destination reads
it only through the record, with `reveal(_:)`, and printing or mirroring it shows `<redacted>`.
`redactingSensitiveValues()` makes a destination's records reveal nothing, and
`droppingCallSite()` removes their call sites; every other destination receives both:

```swift
struct SignedIn: Event {
    var email: Sensitive<String>
}

let backend = InMemoryDestination()
let vendor = InMemoryDestination()
let tracker = Tracker()
let delivery = tracker.records.batch().deliver(
    to: backend,
    vendor.redactingSensitiveValues().droppingCallSite()
)
tracker.track(SignedIn(email: Sensitive("ada@example.com")))
await tracker.finish()
try await delivery.execute()
let event = backend.events(of: SignedIn.self)[0]
let email = backend.records[0].reveal(event.email)    // "ada@example.com"
let redacted = vendor.records[0].reveal(event.email)  // nil
let callSite = vendor.records[0].sourceLocation       // nil
```

### Delivery guarantees

`track` only queues an event; a record exists, in `records` and in a store, once the tracker's
worker has reached it. `await tracker.flush()` waits until it has reached everything tracked so
far; `await tracker.finish()` does too, then ends the records. Records waiting for a delivery are
held in memory without a bound. Records a delivery has read
but not yet delivered are lost to this run if the delivery is cancelled or fails, and so are
batches dropped from a destination's full buffer: without a store they are gone, and with one
they come back on the next launch.
One task reads a tracker's records at a time: a second reading at once traps.

### Persistence

Without a store, records live in memory only: whatever isn't delivered when the process exits is
lost. Give the tracker a `SegmentStore` (module `Persistence`) and the tracker's worker writes each
record to disk before publishing it, and it is delivered on the next launch if this one ends first:

```swift
import Persistence

extension SignedUp: BinaryCodable {
    func encode(to encoder: inout BinaryEncoder) {
        encoder.encode(plan)
    }

    init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
        plan = try decoder.decode()
    }
}

let store = try SegmentStore(events: [SignedUp.self])
let tracker = Tracker(store: store)
let delivery = tracker.records.batch().deliver(to: ConsoleDestination())
```

A record is durable once written, not once `track` returns: one tracked moments before the process
is killed, not yet reached by the worker, is lost. As the app moves to the background, call
`await tracker.flush()`, then `store.synchronize()`.

The store keeps only the event types in `events`, which conform to `BinaryCodable`, a compact
binary encoding written field by field. Any other event is kept in memory only: delivered in this
run, never written. The log is a directory of append-only segment files, in Application Support on
Apple platforms (excluded from backups), and in the XDG state directory on Linux, unless
`directory:` says otherwise. Each segment starts with a magic number and format
version, and each record is framed by its length and CRC-32. A segment is deleted once every record
in it has been delivered, so a log with nothing left to send holds no files.

The log never holds more than its byte bound, 5 MiB unless `byteBound:` says otherwise. When a
record won't fit, the oldest segments are dropped, and each drop is reported on the store's
`dropReports` with the number of records dropped and their timestamp range; so is a record whose
write to disk fails, which is kept in memory only. Recovery cuts a segment at its first torn or
corrupt record, keeps every record before it, and reports what it cut. A record whose delivery had
started when the app ended comes back with `isRedelivered` set, so a destination can tell it may
have been sent before. A record is never sent without that mark on disk first: one whose mark can't
be written waits for a later launch. A segment written by a newer release, in a later format
version, is left untouched after a rollback. The store makes the log durable against power loss too
(`fsync`) once per batch; call `store.synchronize()`, after `tracker.flush()`, as the app moves to
the background or terminates. A recovered record's `ServiceContext` is not kept: it comes back in the top-level
context.

An event declared with `@Event` (below) is `BinaryCodable` already, so a store keeps it with no
conformance written by hand.

An app on Apple platforms that already keeps a GRDB database can keep its records there instead:
`DatabaseStore(events:database:table:byteBound:)` (module `GRDBPersistence`, a product of its own
that `import Traffluent` leaves out) takes the app's `DatabaseQueue` or `DatabasePool` and a table
name, creates the table with a migration of its own, and opens no second SQLite database. It makes
the same promises as `SegmentStore`: the worker commits each record before publishing it, a batch is
marked before it goes out and its rows deleted once delivered, the table is bounded by its records'
encoded bytes with the oldest dropped and reported, and records are encoded the same way.

### Deriving events with `@Event`

`@Event` (module `EventMacros`, a product of its own that `import Traffluent` leaves out, so only
apps that use it build swift-syntax) makes a struct an event from its declaration. It adds the
`Event` and `BinaryCodable` conformances, the event's name and consent category when you give
them, and a `schema`, an `EventSchema` value that tooling reads:

```swift
import EventMacros

@Event(name: "checkout_started", version: 2)
struct CheckoutStarted {
    var cartSize: Int
    var coupon: String?
}

let tracker = Tracker()
tracker.track(CheckoutStarted(cartSize: 3, coupon: nil))
let properties = CheckoutStarted.schema.properties.map(\.name)  // ["cartSize", "coupon"]
```

The schema holds the name, the version, the consent category and each stored property's name, type
as written and optionality, in declaration order. The encoding writes and reads those properties in the same
order, as the hand-written conformance under Persistence does, and a `Sensitive` property keeps its
redaction. `consent:` sets the event's `consentCategory` (`@Event(consent: .advertising)`). A stored
property whose type isn't `BinaryCodable` is a compile error that names it:
`static method 'requireBinaryCodable(position:)' requires that 'Coordinate' conform to 'BinaryCodable'`.
So are `@Event` on anything but a struct and a stored property without a type annotation. Static
and computed properties are left out. The struct keeps its memberwise initializer.

### Exporting a tracking plan

The events' Swift types are their schema's source; a tracking plan, the JSON Schema (draft
2020-12) of every event an app tracks, is exported from them for the people and tools outside the
app. `TrackingPlan` (module `TrackingPlans`, a product of its own that `import Traffluent` leaves
out) turns schemas into the plan's files, one document per event and an index, as values:

```swift
import TrackingPlans

let plan = TrackingPlan(schemas: [CheckoutStarted.schema])
let paths = plan.files.map(\.path)  // ["tracking-plan.json", "checkout_started.v2.schema.json"]
```

The bytes depend on the schemas alone: keys sorted, two-space indentation, a trailing newline and
no timestamps, the same on every run and platform, so the plan can be committed and reviewed.
Each document requires the properties that aren't optional, allows `null` for those that are,
rejects any other property, and carries the event's version and consent category
(`x-traffluent-version`, `x-traffluent-consent-category`); a `Sensitive` property is marked
`x-traffluent-sensitive`. `TrackingPlan`'s documentation lists how each Swift type maps.

A tool can only read the schemas of types it is compiled against, so the plan is written by a small
executable in your package that lists your events:

```swift
// Package.swift
.executableTarget(name: "AppTrackingPlan", dependencies: [
    "AppEvents",
    .product(name: "TrackingPlans", package: "Traffluent"),
]),
```

```swift
// Sources/AppTrackingPlan/AppTrackingPlan.swift
import AppEvents
import TrackingPlans

@main
struct AppTrackingPlan: TrackingPlanCommand {
    static let trackingPlan = TrackingPlan(schemas: [
        CheckoutStarted.schema,
        SignedUp.schema,
    ])
}
```

Then one command, from the package's directory, builds it and writes the plan into `TrackingPlan/`:

```sh
swift package --allow-writing-to-package-directory export-tracking-plan
```

The `export-tracking-plan` plugin runs the package's one executable target that depends on
`TrackingPlans`; `--product <name>` picks one of several, and `--output <directory>` writes
elsewhere in the package. Writing again deletes the documents of events the plan no longer lists.
[`Examples/Sources/StoreTrackingPlan`](Examples/Sources/StoreTrackingPlan) is such an executable,
and [`Examples/TrackingPlan`](Examples/TrackingPlan) the plan it writes (`just example-tracking-plan`).

## Logging, tracing, metrics and analytics

Each signal has one job: logs are for the developer debugging, traces for where time went, metrics
for alerts, and analytics for what people do in the product. [Logging, Tracing, Metrics and
Analytics](https://tyler-keith-thompson.github.io/Traffluent/documentation/traffluent/whatgoeswhere)
says which facts go where, with the anti-patterns to avoid.

## Modules

| Module | Holds |
|---|---|
| `Events` | `Event`: the protocol typed analytics events conform to, with its `ConsentCategory`; `Sensitive`, a property value destinations read only through its record; `EventSchema`, an event type's name, version, consent category and stored properties as a value; and `EventRecord`: a tracked event with its timestamp, `SourceLocation`, `ServiceContext`, redelivery marker and the `DeliveryTag` of the store that keeps it |
| `Destinations` | `Destination`, where batches of records are delivered; `ConsoleDestination`, which prints them; `deliver(to:)`, which hands each batch of a sequence to every destination; `batch()`, the default batching; and the destination modifiers `accepting(_:)`, `redactingSensitiveValues()` and `droppingCallSite()` |
| `DestinationTesting` | `InMemoryDestination`: keeps every batch it receives, so tests read what was tracked |
| `LoggingDestinations` | `LoggerDestination`: writes each event to a swift-log `Logger`, with its call site and context as metadata |
| `TracingDestinations` | `SpanEventDestination`: adds each event to the span that was active when it was tracked |
| `HTTPDestinations` | `HTTPDestination`: sends each batch to an HTTP endpoint as one request, its body written by a `BatchEncoder` and its first record's trace context in the header fields, through an `HTTPTransport`; `URLSessionTransport`, the default transport |
| `Trackers` | `Tracker`: records each tracked event as one of its `records`, writing it first to a store when it has one, bound to a task with `withTracker` and read with `Tracker.current`; `Enricher`, which adds to each record's context; and `Consent`, which delivers, holds or drops each event by its category's `ConsentStatus`, reporting every drop as a `ConsentDropReport` |
| `Checksums` | `CRC32`: the CRC-32 checksum of raw bytes |
| `Persistence` | `RecordStore`, where a tracker keeps each record until it is delivered; `SegmentStore`, the default, a size-bounded log of append-only segment files that reports every drop as a `DropReport`; and `BinaryCodable`, the binary encoding persisted events opt into |
| `GRDBPersistence` | `DatabaseStore`: a `RecordStore` that keeps records in a table of the app's own GRDB database, size-bounded, reporting every drop; Apple platforms only, and left out of `import Traffluent` |
| `EventMacros` | `@Event`: derives a struct's `Event` and `BinaryCodable` conformances, its name and its `EventSchema` from its declaration; left out of `import Traffluent`, so only apps that use it build swift-syntax |
| `TrackingPlans` | `TrackingPlan`: the JSON Schema (draft 2020-12) of every event an app tracks, one document per event and an index, exported from their `EventSchema` values; `TrackingPlanCommand`, the executable that writes one, which the `export-tracking-plan` command plugin runs; left out of `import Traffluent` |

## Examples

Small apps that track typed events with a `Tracker` and deliver them to a `ConsoleDestination`,
one per platform. Each builds its tracker and starts its delivery where it starts. They live in
[`Examples/`](Examples), a package of their own that depends on this one.

| Platform | Example | Build |
|---|---|---|
| iPhone and iPad | [`Examples/Apps/ExampleApp`](Examples/Apps/ExampleApp), one universal app | `just example-ios` |
| Mac | [`Examples/Apps/ExampleApp`](Examples/Apps/ExampleApp) | `just example-mac` |
| Mac Catalyst | [`Examples/Apps/ExampleApp`](Examples/Apps/ExampleApp), the iOS app built for the Mac | `just example-catalyst` |
| visionOS | [`Examples/Apps/ExampleApp`](Examples/Apps/ExampleApp) | `just example-visionos` |
| watchOS | [`Examples/Apps/ExampleApp`](Examples/Apps/ExampleApp) | `just example-watchos` |
| Linux | [`Examples/Sources/CommandLineExample`](Examples/Sources/CommandLineExample) | `just example-linux` (Docker) |
| Server | [`Examples/Sources/ServerExample`](Examples/Sources/ServerExample), on Hummingbird | `just example-server`, `just serve-example` |

The events are in [`ExampleEvents`](Examples/Sources/ExampleEvents), the screen the Apple apps
share in [`ExampleViews`](Examples/Sources/ExampleViews), and the server's routes and tracking
middleware in [`ExampleServer`](Examples/Sources/ExampleServer). `just examples` builds them all;
`just examples-test` runs their tests.

## Development

Bazel is the development build; SwiftPM is the published package. Both are generated from
`scripts/modules.py`.

| Command | Does |
|---|---|
| `just test` | Build and run every test |
| `just verify` | The tests under Bazel and under SwiftPM |
| `just modules` | Regenerate `Package.swift` and every `BUILD.bazel` |
| `just docs` | The DocC site into `.build/docs` |
| `just bench` | The benchmarks (`Benchmarks/README.md`) |
| `just generate` | An Xcode project from the Bazel graph, in `xcode/` |

`AGENTS.md` describes the layout, the workflow and the house rules in full.

## License

Apache 2.0. See `LICENSE`.
