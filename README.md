# Traffluent

Traffluent is a vendor-neutral analytics library for Swift. Each event is a Swift type, so its
name and properties are checked by the compiler instead of living in a string and a
`[String: Any]` bag. A tracker records the events, and a delivery sends each batch of them to as
many destinations as you like. Traffluent also batches, persists records on disk, retries failed
sends to a server with backoff until they arrive, holds events until the user consents, enforces
each event's schema and tracks screens, controls and the app's lifecycle automatically. It is
built for Swift 6 strict concurrency, has no singletons, and runs on Apple platforms and Linux.
Apps that would otherwise write their own typed event layer can use it instead, with vendor SDKs
as plain destinations.

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

## Example

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

`track` returns at once, from any thread. A worker the tracker owns records the event, and the
delivery batches the records and hands each batch to its destinations when `execute()` runs.

## Guides

- [Tracking Events](https://tyler-keith-thompson.github.io/Traffluent/documentation/traffluent/trackingevents): trackers, batching, enrichers and what a delivery guarantees
- [Choosing Destinations](https://tyler-keith-thompson.github.io/Traffluent/documentation/traffluent/choosingdestinations): logs, traces, a server, memory, and redacting what a destination sees
- [Tracking from SwiftUI, UIKit and AppKit](https://tyler-keith-thompson.github.io/Traffluent/documentation/traffluent/trackingfromviews): the tracker in the environment, a trait or the responder chain
- [Testing What Your Code Tracks](https://tyler-keith-thompson.github.io/Traffluent/documentation/traffluent/testingwhatyoutrack): `withRecordingTracker`
- [Automatic Tracking](https://tyler-keith-thompson.github.io/Traffluent/documentation/traffluent/automatictracking): screen views, control activations and the app's lifecycle
- [Sessions and Standard Context](https://tyler-keith-thompson.github.io/Traffluent/documentation/traffluent/sessionsandstandardcontext): the session, app, device, system, locale and network on every event
- [Sampling Events](https://tyler-keith-thompson.github.io/Traffluent/documentation/traffluent/samplingevents): a seeded fraction of events or sessions
- [Consent Gating](https://tyler-keith-thompson.github.io/Traffluent/documentation/traffluent/consentgating): holding, delivering and dropping events by consent category
- [Persisting Records](https://tyler-keith-thompson.github.io/Traffluent/documentation/traffluent/persistingrecords): the on-disk log, its bounds and recovery, and GRDB
- [Defining Events](https://tyler-keith-thompson.github.io/Traffluent/documentation/traffluent/definingevents): `@Event` and constrained properties
- [Exporting and Checking a Tracking Plan](https://tyler-keith-thompson.github.io/Traffluent/documentation/traffluent/trackingplanworkflow): the JSON Schema of your events, and a check that fails when they drift
- [Logging, Tracing, Metrics and Analytics](https://tyler-keith-thompson.github.io/Traffluent/documentation/traffluent/whatgoeswhere): which facts go to which signal
- [Changing an Event](https://tyler-keith-thompson.github.io/Traffluent/documentation/traffluent/changingevents): which changes need a new version
- [Identifying People](https://tyler-keith-thompson.github.io/Traffluent/documentation/traffluent/identifyingpeople): identifiers that outlive a session
- [Privacy Manifests](https://tyler-keith-thompson.github.io/Traffluent/documentation/traffluent/privacymanifests): what each module collects, for your app's manifest

## Modules

- [`Events`](https://tyler-keith-thompson.github.io/Traffluent/documentation/events): `Event`, `Sensitive`, `Refined`, `EventSchema` and `EventRecord`
- [`Trackers`](https://tyler-keith-thompson.github.io/Traffluent/documentation/trackers): `Tracker`, `Enricher`, `Consent` and `Sampler`
- [`Destinations`](https://tyler-keith-thompson.github.io/Traffluent/documentation/destinations): `Destination`, `ConsoleDestination`, `InMemoryDestination`, `batch()` and `deliver(to:)`
- [`LoggingDestinations`](https://tyler-keith-thompson.github.io/Traffluent/documentation/loggingdestinations): `LoggerDestination`, which writes events to a swift-log `Logger`
- [`TracingDestinations`](https://tyler-keith-thompson.github.io/Traffluent/documentation/tracingdestinations): `SpanEventDestination`, which adds events to the active span
- [`HTTPDestinations`](https://tyler-keith-thompson.github.io/Traffluent/documentation/httpdestinations): `HTTPDestination`, which posts each batch to an HTTP endpoint and retries it until it arrives
- [`CollectorEncoding`](https://tyler-keith-thompson.github.io/Traffluent/documentation/collectorencoding): `CollectorBatchEncoder`, TraffluentCollector's ingest format
- [`SwiftUITracking`](https://tyler-keith-thompson.github.io/Traffluent/documentation/swiftuitracking): The environment's `tracker` and the `trackOnAppear`, `trackOnTap`, `trackChange` and `trackScreen` modifiers
- [`UIKitTracking`](https://tyler-keith-thompson.github.io/Traffluent/documentation/uikittracking): `TrackerTrait` and `UIControl.track(_:for:)`
- [`AppKitTracking`](https://tyler-keith-thompson.github.io/Traffluent/documentation/appkittracking): `TrackerProviding`, `NSView.tracker` and `NSControl.track(_:)`
- [`AutomaticScreenTracking`](https://tyler-keith-thompson.github.io/Traffluent/documentation/automaticscreentracking): `trackScreensAutomatically`: opt-in screen views, without swizzling
- [`AutomaticControlTracking`](https://tyler-keith-thompson.github.io/Traffluent/documentation/automaticcontroltracking): `trackControlsAutomatically`: opt-in UIKit control activations, without swizzling
- [`LifecycleTracking`](https://tyler-keith-thompson.github.io/Traffluent/documentation/lifecycletracking): `trackLifecycle`: installs, updates, opens, backgrounding and termination
- [`Sessions`](https://tyler-keith-thompson.github.io/Traffluent/documentation/sessions): `Enricher.sessions`: a session identifier held in memory only
- [`StandardContext`](https://tyler-keith-thompson.github.io/Traffluent/documentation/standardcontext): Enrichers for the app, device, operating system, locale, network and identifier for vendor
- [`Checksums`](https://tyler-keith-thompson.github.io/Traffluent/documentation/checksums): `CRC32`
- [`Persistence`](https://tyler-keith-thompson.github.io/Traffluent/documentation/persistence): `RecordStore`, `SegmentStore` and `BinaryCodable`
- [`GRDBPersistence`](https://tyler-keith-thompson.github.io/Traffluent/documentation/grdbpersistence): `DatabaseStore`, a store in the app's GRDB database (not in `import Traffluent`)
- [`EventMacros`](https://tyler-keith-thompson.github.io/Traffluent/documentation/eventmacros): `@Event` and `@Constrained` (not in `import Traffluent`)
- [`TrackingPlans`](https://tyler-keith-thompson.github.io/Traffluent/documentation/trackingplans): `TrackingPlan`, its check and `TrackingPlanCommand` (not in `import Traffluent`)
- [`TrackingPlanTesting`](https://tyler-keith-thompson.github.io/Traffluent/documentation/trackingplantesting): `expectTrackingPlan(_:matches:)`, for test targets (not in `import Traffluent`)
- [`TrackerTesting`](https://tyler-keith-thompson.github.io/Traffluent/documentation/trackertesting): `withRecordingTracker`, for test targets (not in `import Traffluent`)

[`Examples/`](Examples) holds an example app for each platform, a command-line tool and a server
(`Examples/README.md`). `AGENTS.md` describes how to build and test Traffluent.

## License

Apache 2.0. See `LICENSE`.
