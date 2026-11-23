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
those a `Tracker`, or, in SwiftUI, read it from the environment (below). With no tracker bound,
`Tracker.current` drops each event and logs it at debug level.

Every record also carries the `ServiceContext` it was tracked in (swift-distributed-tracing's
`Instrumentation` module), read through typed keys, so a destination can see the session, the
screen or the active span's trace without a string-keyed bag. `Enricher`s add to it as each event
is tracked:

```swift
import Instrumentation

enum ExperimentKey: ServiceContextKey {
    typealias Value = String
}

let experiment = Enricher { context in
    context[ExperimentKey.self] = "new-checkout"
}
let tracker = Tracker(enrichers: [experiment])
tracker.track(SignedUp(plan: "pro"))  // its record's context[ExperimentKey.self] is "new-checkout"
```

`tracker.enriched(by:)` gives the part of an app a value belongs to a copy of the tracker whose
events alone carry it, such as a screen's name, where a task-local context doesn't reach. The
copy shares the tracker's records; the worker runs its enricher before the tracker's own.

### SwiftUI

On Apple platforms, views read the tracker from the environment (module `SwiftUITracking`, empty
elsewhere). Set it at the root of the views with `tracker(_:)`, read it in any view with
`@Environment(\.tracker)`, and let modifiers track what views do:

```swift
import SwiftUI

struct PlanSelected: Event {
    var plan: String
}

struct CheckoutView: View {
    @Environment(\.tracker) private var tracker
    @State private var plan = "free"

    var body: some View {
        Form {
            Picker("Plan", selection: $plan) {
                Text("Free").tag("free")
                Text("Pro").tag("pro")
            }
            .trackChange(of: plan) { PlanSelected(plan: $0) }
            Button("Sign up") {
                tracker.track(SignedUp(plan: plan))  // its record's context[ScreenKey.self] is "Checkout"
            }
        }
    }
}

let tracker = Tracker()
let root = CheckoutView()
    .trackScreen("Checkout")  // tracks ScreenViewed(screen: "Checkout") each time it appears
    .tracker(tracker)
```

Each modifier tracks through the environment's tracker, once per trigger, and records where it is
applied as the call site. `trackOnAppear(_:)` tracks its event each time the view appears, as
`onAppear` runs: again when a navigation stack pops back to it, not when SwiftUI only redraws it.
`trackOnTap(_:)` tracks each tap, beside the view's own action. `trackChange(of:_:)` tracks the
event it makes from each new value, not from the first one or an equal one. `trackScreen(_:)`
tracks `ScreenViewed` each time the view appears, and puts a tracker enriched with the screen's
`ScreenKey` in the environment inside it, so the events tracked from its actions and modifiers
carry the screen's name. Apply it where the screen's view is placed, as above: a view's own
`@Environment` reads the environment around it, which the modifiers in its own body don't change.
Until a tracker is set, the environment's is `Tracker.noOp`, so a preview tracks nothing.

### UIKit and AppKit

In UIKit (module `UIKitTracking`: iOS, iPadOS, tvOS, visionOS and Mac Catalyst), the tracker is a
trait. Set it on the window scene as it connects, and every view controller and view in the scene
inherits it, as SwiftUI views inherit their environment. Read it in an action with
`traitCollection.tracker`, or let `track(_:for:)` track a control's events:

```swift
import UIKit

struct ShareTapped: Event {}

final class CheckoutViewController: UIViewController {
    let share = UIButton(configuration: .filled())

    override func viewDidLoad() {
        super.viewDidLoad()
        share.track(ShareTapped())  // through the tracker the button's traits hold when it is tapped
        share.addTarget(self, action: #selector(signUp(_:)), for: .primaryActionTriggered)
        view.addSubview(share)
    }

    @objc func signUp(_ sender: UIButton) {
        sender.traitCollection.tracker.track(SignedUp(plan: "pro"))
    }
}

// In the scene delegate's scene(_:willConnectTo:options:):
windowScene.traitOverrides.tracker = tracker
```

In AppKit (module `AppKitTracking`, macOS), a view finds its tracker the way an action finds its
target: `NSView.tracker` asks the view's responder chain (its superviews and view controllers, its
window and window controller), then the window's delegate and the application's delegate, for the
first that conforms to `TrackerProviding`. `track(_:)` tracks an event each time a control sends
its action, just before the action:

```swift
import AppKit

final class CheckoutWindowController: NSWindowController, TrackerProviding {
    let tracker: Tracker

    init(window: NSWindow, tracker: Tracker) {
        self.tracker = tracker
        super.init(window: window)
    }

    required init?(coder: NSCoder) { nil }

    @objc func signUp(_ sender: NSButton) {
        sender.tracker.track(SignedUp(plan: "pro"))
    }
}

let share = NSButton(title: "Share", target: nil, action: nil)
share.track(ShareTapped())  // through the tracker of the window it is in when it is clicked
```

Neither needs a global or swizzling. The tracker is found when the action fires, so each scene or
window can have a tracker of its own, a view controller can override it for the views below it
(with a tracker `enriched(by:)` a screen's name, say), and a control moved to another window tracks
through that window's. `track(_:for:)` adds a `UIAction` beside the control's other actions and
returns it, for `removeAction(_:for:)`. An `NSControl` has one target and action, so `track(_:)`
puts its own in their place and sends the control's action on to its target, or up the responder
chain when it had none; call it after setting them. SwiftUI's `\.tracker` and UIKit's trait are one
value: SwiftUI views hosted in UIKit read the scene's tracker, and UIKit views hosted in SwiftUI read
the environment's.

### Automatic screen views

Screens can track their own views (module `AutomaticScreenTracking`: iOS, iPadOS, tvOS, visionOS,
Mac Catalyst and macOS). Nothing is tracked until a window scene, or on macOS a window, turns it
on:

```swift
import AutomaticScreenTracking

// In the scene delegate's scene(_:willConnectTo:options:), beside the scene's tracker:
windowScene.traitOverrides.tracker = tracker
windowScene.trackScreensAutomatically { screen in
    switch screen.name {
    case "DebugMenuViewController": nil  // not tracked
    case "CheckoutView": ScreenViewed(screen: "Checkout")
    default: ScreenViewed(screen: screen.name)
    }
}
```

A screen is a view controller on screen none of whose children is: the one a navigation controller
shows, a tab's, one presented. It tracks `ScreenViewed` as it appears, and again when a pop or a
dismissal reveals it, named after its controller's type, or for a hosting controller after the
SwiftUI view it shows, such as each view a `NavigationStack` pushes on iOS. The closure gets each
`DiscoveredScreen`, its name and kind, and returns the event to track, renamed, or `nil` to skip it;
leave it out to track every screen under its own name. `kinds:` turns off UIKit's (or AppKit's)
view controllers or SwiftUI's views. A SwiftUI screen given `trackScreen(_:)` is left to it, so it
isn't tracked twice. Each screen view goes through the tracker the screen's traits hold, so each
scene keeps its own; on macOS, `window.trackScreensAutomatically()` tracks through the tracker the
screen's view finds up its responder chain. There, a `NavigationStack` draws what it pushes without
a view controller, so give those views `trackScreen(_:)`. It swizzles nothing: the scene owns it,
and it looks at the scene's view controllers after each turn of the main run loop.

### Automatic control activations

UIKit controls can track their own activations too (module `AutomaticControlTracking`: iOS,
iPadOS, tvOS, visionOS and Mac Catalyst). Nothing is tracked until a window scene turns it on:

```swift
import AutomaticControlTracking

// In the scene delegate's scene(_:willConnectTo:options:), beside the scene's tracker:
windowScene.traitOverrides.tracker = tracker
windowScene.trackControlsAutomatically { control in
    switch control.identifier {
    case "debug-menu-button": nil  // not tracked
    case "checkout-button": ControlActivated(control: "Checkout", kind: control.kind)
    case let identifier?: ControlActivated(control: identifier, kind: control.kind)
    case nil: nil  // no identifier: not tracked
    }
}
```

Each time a touch activates a UIKit control in the scene's windows (a button tapped, a switch
flipped), it tracks one `ControlActivated`, named after the control's `accessibilityIdentifier` and
never its title or other text, with its kind, the first public UIKit class it is (`"UIButton"`).
The closure gets each `DiscoveredControl`, its identifier, kind and screen, and returns the event,
renamed, or `nil` to skip it; leave it out to track every control that has an identifier under it.
A touch that ends off the control tracks nothing, and neither do activations without a touch, such
as VoiceOver's, or, but for a control the last touch was on and didn't activate, actions the app
sends itself. Each record's context carries the control's
screen, the type of the view controller it is in, as `ScreenKey`, unless the tracker's enrichers
set one. SwiftUI's controls are never tracked automatically: give them `trackOnTap(_:)`. A UIKit
control inside a SwiftUI view is left out with them. Each activation goes through the tracker the
control's traits hold, so each scene keeps its own. It swizzles nothing: the scene owns it, and it
adds a gesture recognizer to each of the scene's windows that notes the control a touch begins on
and never recognizes, so it holds no touch up, and a target to that control. macOS has no equivalent:
an `NSControl` has one target, so give its controls `track(_:)`.

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

To read what was tracked inside the app, deliver to an `InMemoryDestination` too (module
`Destinations`): an event inspector in a debug build, a recent-activity view, a SwiftUI preview,
or a test of what your code tracks. It keeps the newest 1,000 records, or as many as you pass as
`capacity:`, dropping the oldest across batches; `InMemoryDestination.unbounded()` keeps every one.
Read it with `events(of: SignedUp.self)`, `records` or `batches`, or wait on `deliveries`, which
announces each batch to one reader.

### Testing what your code tracks

To check what your code tracks from a test, add the `TrackerTesting` product to the test target.
`withRecordingTracker` binds a fresh tracker to the test's task for its body, then returns every
event tracked in it, in order, with `SignedUp` `Equatable`:

```swift
import Testing
import TrackerTesting

@Test func signingUpTracksThePlan() async {
    let tracked = await withRecordingTracker {
        Tracker.current.track(SignedUp(plan: "pro"))
    }
    #expect(tracked.events(of: SignedUp.self) == [SignedUp(plan: "pro")])
}
```

Each call has a tracker of its own, so tests running at once never see each other's events. The
body may be sync or async, and may return a value, read as `tracked.value`. `tracked.names` lists
every event's name and `tracked.records` every record. Code handed its tracker rather than reading
`Tracker.current`, such as a SwiftUI view given it with `tracker(_:)`, takes the one the body is
given: `withRecordingTracker { tracker in … }`.

### App lifecycle

The app's lifecycle can track itself too (module `LifecycleTracking`: every platform). Nothing is
tracked until the app turns it on, as it launches, and keeps what it returns:

```swift
import LifecycleTracking

let store = try SegmentStore(events: [ApplicationOpened.self, ApplicationBackgrounded.self, SignedUp.self])
let tracker = Tracker(store: store)
// In the application delegate's application(_:didFinishLaunchingWithOptions:), kept beside the tracker:
let lifecycle = tracker.trackLifecycle(
    kinds: [.installed, .updated, .opened, .backgrounded],
    versionStore: FileVersionStore(directory: store.directory)
)
let delivery = tracker.records
    .batch(strategy: .either(.count(20), .time(interval: .seconds(30), clock: ContinuousClock()), .lifecycle))
    .deliver(to: ConsoleDestination())
```

As it starts, it compares the app's version (`CFBundleShortVersionString`, or `version:`) with the
one its `VersionStore` saved at the last launch: none tracks `ApplicationInstalled`, another
`ApplicationUpdated(previousVersion:version:)`, the same neither. The store keeps the version and
nothing else; `FileVersionStore` keeps it in a file beside the records, `InMemoryVersionStore` in
memory for tests, and any type of yours can conform. Then it tracks `ApplicationOpened(fromBackground:
false)`, and after that, from `UIApplication`'s, `WKApplication`'s or `NSApplication`'s
notifications, `ApplicationBackgrounded`, `ApplicationOpened(fromBackground: true)` and, where the
platform reports it, `ApplicationTerminated`, each once per transition. A scene-based app gets one
transition for the whole app, not one per scene. On macOS another app becoming active counts as the
background. `kinds:` turns kinds off. On Linux, a server or tool calls `await lifecycle.finish()` as
it ends, which tracks `ApplicationTerminated`.

As the app leaves the foreground, it waits for the tracker's worker to write every record tracked so
far to the store, then calls the store's `synchronize()`, so a record accepted before the app went
to the background survives it being killed there. A delivery batched with `.lifecycle` sends what
is pending as it reads the `ApplicationBackgrounded` record. The notification's handler only hands
the transition on: the work runs on a task of its own, never on the main thread, and on platforms
that suspend apps it holds background time from `ProcessInfo.performExpiringActivity` until done.

### Sessions

Every event can carry the session it was tracked in (module `Sessions`: every platform). Nothing is
put in a session until the app adds the sessions enricher to the ones it builds its tracker with:

```swift
import Sessions

let tracker = Tracker(enrichers: [.sessions(timeout: .seconds(30 * 60))])
tracker.track(SignedUp(plan: "pro"))  // its record's context[SessionKey.self] is the session's UUID
```

The tracker's worker sets each record's `SessionKey` to its session's identifier, through every copy
of the tracker, the environment's and the traits' included. A session goes on while each event comes
less than the timeout (30 minutes by default) after the one before it, measured between the events'
timestamps, when each was tracked; the first event after that starts a new session. So the app coming
back from the background past the timeout starts a new session with its first event, such as
`ApplicationOpened`, without `Sessions` and `LifecycleTracking` knowing about each other.

`SessionStarted` comes before each session's first event, at its time, and, from the second session
on, `SessionEnded(duration:)` before that, stamped with the time of the ended session's last event,
its duration running from the session's first event to its last. A session ends only when an event
comes after the timeout, so a run's last session has no `SessionEnded`: a destination takes its end
from its last event. `kinds:` turns either event off, or both, and every record still carries its
session's key.

The identifier is a random UUID, derived from nothing, and lives in the enricher's memory only:
neither the tracker nor its store writes it to disk (a store keeps no record's context), and the
next launch's tracker starts a new session with a new identifier. Traffluent keeps no identifier
that links one session to another.

### Standard context

Every event can carry what most analytics want beside it: the app, the device, the operating
system, the locale and the network connection (module `StandardContext`: every platform). Each is an
enricher of its own, so nothing is added until the app adds it:

```swift
import StandardContext

let tracker = Tracker(enrichers: [.application(), .device(), .operatingSystem(), .locale(), .network()])
tracker.track(SignedUp(plan: "pro"))  // its record's context[OperatingSystemKey.self]?.name is "iOS" on an iPhone
```

Each sets a typed key whose value is a small struct a destination reads from each record's context:
`ApplicationKey` (bundle identifier, version and build), `DeviceKey` (model identifier and form
factor), `OperatingSystemKey` (name and version), `LocaleKey` (a `Locale`, with its identifier,
language and region) and `NetworkKey` (Wi-Fi, cellular, wired Ethernet, another kind, or offline).
The app, device, system and locale are read once, as the enricher is made, never per event. The
network connection changes, so its enricher starts an `NWPathMonitor` of its own, which stops when
the last tracker holding the enricher goes, and sets the latest connection on each event.

Off Apple platforms there is no device and no path monitor, so those enrichers set nothing, and a
process there usually has no Info.plist: a server or tool passes its own app.

```swift
let tracker = Tracker(enrichers: [
    .application(ApplicationKey.Value(bundleIdentifier: "com.example.server", version: "1.2.0", build: "42")),
    .operatingSystem(),
])
```

`.vendorIdentifier()`, made on the main actor, adds the platform's `identifierForVendor` as
`VendorIdentifierKey`: the operating system owns it, gives it to every app of one vendor on the
device, and resets it once they are all removed. Of the identifiers Traffluent offers, it is the
only one that outlives a session. Nothing carries it unless the app adds the enricher, and the app
owns that decision and the user's consent to it. Traffluent never writes it to disk nor makes one
up: on macOS and Linux, which have none, records carry no key. It is a `Sensitive` value, so a
destination given `redactingSensitiveValues()` never receives it.

### Sampling

A tracker can keep a fraction of the events it tracks, event by event or a whole session at once
(module `Trackers`; sessions from module `Sessions`). Nothing is sampled until the app gives the
tracker its samplers:

```swift
import Sessions

struct Scrolled: Event {
    var offset: Int
}

let tracker = Tracker(
    enrichers: [.sessions()],
    samplers: [.events(of: Scrolled.self, rate: 0.1), .sessions(rate: 0.5)]
)
tracker.track(Scrolled(offset: 120))  // if kept, its record's context[SampleRateKey.self]?.value is 0.05
```

`.events(of:rate:)` keeps each event of a type with the probability its `SampleRate` gives, and
`.events(where:rate:)` each record a predicate selects, deciding each event on its own.
`.sessions(rate:)` keeps or drops every record of a session alike, its `SessionStarted` and
`SessionEnded` with it; `.grouped(by:rate:)` does the same for the groups any context key's values
make. A rate is in 0 ... 1: a literal outside it, or `SampleRate(_:)` given one, traps, and
`SampleRate(checked:)` throws `InvalidSampleRate` instead. A record is kept only if every sampler
that applies to it keeps it, and a kept record carries the product of their rates as its
`SampleRateKey`, so a destination can count it as `1 / value` records. One no sampler applies to
is always kept and carries no key.

The tracker's worker samples each record after its enrichers, whose keys a sampler can read, and
before its consent and its store, so a dropped event is never held, written to disk or delivered.
Each drop is reported on `samplingDropReports`, merged one report per event type while unread, as
rejections are. The decisions come from the tracker's `samplingSeed`, drawn from the system's
random number generator once per tracker unless you pass one, and are the same on every platform
and Swift release, so with a seed fixed, which events are kept is fixed too:

```swift
let tracker = Tracker(samplers: [.events(of: Scrolled.self, rate: 0.1)], samplingSeed: 42)
for offset in 0 ..< 100 {
    tracker.track(Scrolled(offset: offset))
}
await tracker.finish()
for await report in tracker.samplingDropReports {
    print(report)  // Scrolled: 89 sampled out
}
```

A session's decision is made from the seed and the session's identifier alone, so nothing records
it: the sampler keeps only the current session's decision, in memory, and never writes the
identifier anywhere. Records a store recovered from an earlier run were sampled in that run, and
come back in the top-level context, without their rate.

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
`await tracker.flush()`, then `store.synchronize()`, or let `trackLifecycle` (above) do both.

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

### Constraining properties

A property's type says what kind of value it holds; a constraint says which values of that kind
are valid. A rule the type can enforce belongs in the type: a `Refined` value satisfies every
constraint of its `Refinement` from the moment it is made. Rules a plain `String` or `Int` can't
carry are declared beside the property with `@Constrained` (module `EventMacros`), and checked by
the tracker:

```swift
enum CouponCode: Refinement {
    static let constraints: [Constraint<String>] = [.pattern("^[A-Z0-9]{6}$", example: "SPRING")]
}

@Event(name: "search_performed")
struct SearchPerformed {
    @Constrained(.minLength(1), .maxLength(200))
    var query: String
    @Constrained(.minimum(0))
    var resultCount: Int
    var coupon: Refined<String, CouponCode>?
}

let coupon = try? Refined<String, CouponCode>(checked: "spring")  // nil: UnsatisfiedConstraint.pattern
let tracker = Tracker()
tracker.track(SearchPerformed(query: "", resultCount: 3, coupon: Refined("SPRING")))
await tracker.finish()
for await report in tracker.rejectionReports {
    print(report)  // search_performed: "query" breaks minLength 1 (1 rejected)
}
```

The keywords are JSON Schema's: `minLength` and `maxLength` (in Unicode scalars) and `pattern`
for a string, `minimum` and `maximum` for a number, `minItems` and `maxItems` for an array. Each is
offered only for the types it applies to, with its bound in the property's own type, so
`.minLength` on an `Int` or `.minimum(0.5)` on an `Int` is a compile error. In `@Constrained`, so
is a lower bound above its upper bound, a pattern that doesn't compile, and a pattern whose
`example` it, or another keyword of the property, rejects; in a `Refinement`, those trap when its
constraints are built. `Refined`'s plain initializer traps on a value that breaks its rule, as an
`Array` subscript does out of range; `init(checked:)` throws the `UnsatisfiedConstraint` instead.

The tracker's worker checks each event's declared constraints before anything else, never on the
caller. An event that breaks one is rejected: never enriched, held by a consent, written to a
store or delivered. Each rejection is reported on `tracker.rejectionReports`, as a
`RejectionReport` naming the event, the property and the keyword, and in debug builds logged at
error level too. Unread reports merge, one per event, property and keyword, counting the rejections
and the range of times they were tracked, so a broken call site in a loop can't fill memory. A
record a store recovered from an earlier run is checked again, and the store forgets one that a
constraint added since rejects; a stored `Refined` value its rule no longer accepts doesn't decode,
and the store reports it. A `Sensitive` property takes no `@Constrained` keywords, as checking one
would reveal it; a `Sensitive<Refined<…>>` enforces its rule as it is made.

Both kinds of constraint are part of the event's schema, so the exported tracking plan lists them
beside each property's type, and each example payload satisfies them (a pattern's `example` is
the one used). An array's `Refined` elements are checked as they are made, but their rules aren't
exported.

### Exporting a tracking plan

The events' Swift types are their schema's source; a tracking plan, the JSON Schema (draft
2020-12) of every event an app tracks, is exported from them for the people and tools outside the
app. `TrackingPlan` (module `TrackingPlans`, a product of its own that `import Traffluent` leaves
out) turns schemas into the plan's files, one document per event and an index, as values:

```swift
import TrackingPlans

let plan = TrackingPlan(schemas: [CheckoutStarted.schema])
let paths = plan.files.map(\.path)
// ["tracking-plan.json", "checkout_started.v2.schema.json", "checkout_started.v2.example.json"]
```

The bytes depend on the schemas alone: keys sorted, two-space indentation, a trailing newline and
no timestamps, the same on every run and platform, so the plan can be committed and reviewed.
Each document requires the properties that aren't optional, allows `null` for those that are,
rejects any other property, and carries the event's version and consent category
(`x-traffluent-version`, `x-traffluent-consent-category`); a `Sensitive` property is marked
`x-traffluent-sensitive`. `TrackingPlan`'s documentation lists how each Swift type maps.
Beside each document is the event's example, a conformance vector: the payload with every property
set to a fixed value its schema accepts (`"example"`, 0, `false`, one array element), which another
platform's client can encode the same event against.

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

### Checking the tracking plan

The committed plan is the contract every platform sending the events agrees on. One command fails
when the Swift events no longer match it, with a line naming each event and property that changed:

```sh
swift package check-tracking-plan
```

A difference is breaking when a payload the committed plan accepts may be one the events' plan
rejects now: a removed or renamed event, a removed property, a retyped one, an optional property
made required, or a new required property. Anything else (a new event, a new optional property, a
changed consent category) leaves the committed plan out of date, which fails with its own message
telling you to export it again. A constraint is compared keyword by keyword: tightening one (a
higher `minLength` or `minimum`, a lower `maxLength` or `maximum`, a new bound, a new or changed
`pattern`) is breaking, and loosening one only leaves the plan out of date. An integer type
narrowed to one of fewer bits tightens its bounds the same way. Raising an event's version (`@Event(version: 3)`) is how a breaking
change is made on purpose: the new version gets a document of its own. `--plan <directory>` checks
a plan committed elsewhere, and `--product <name>` picks the executable as export's does.

The same check runs from a test, so it runs wherever the app's tests do. Add the `TrackingPlanTesting`
product to a test target that depends on the executable:

```swift
import Foundation
import Testing
import TrackingPlanTesting
@testable import AppTrackingPlan

@Test func eventsMatchTheTrackingPlan() {
    let plan = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("TrackingPlan")
    expectTrackingPlan(AppTrackingPlan.trackingPlan, matches: plan)
}
```

It records an issue with the report the command prints. `TrackingPlan.check(against:)` returns
the same comparison as a value, each `TrackingPlanDifference` with whether it `isBreaking`.
[`Examples/Tests/StoreTrackingPlanTests`](Examples/Tests/StoreTrackingPlanTests) is such a test.

## Logging, tracing, metrics and analytics

Each signal has one job: logs are for the developer debugging, traces for where time went, metrics
for alerts, and analytics for what people do in the product. [Logging, Tracing, Metrics and
Analytics](https://tyler-keith-thompson.github.io/Traffluent/documentation/traffluent/whatgoeswhere)
says which facts go where, with the anti-patterns to avoid.

## Modules

| Module | Holds |
|---|---|
| `Events` | `Event`: the protocol typed analytics events conform to, with its `ConsentCategory`; `Sensitive`, a property value destinations read only through its record; `Refined`, a value that satisfies its `Refinement`'s `Constraint`s from the moment it is made; `EventSchema`, an event type's name, version, consent category and stored properties, with each one's `ValidationKeyword`s, as a value; and `EventRecord`: a tracked event with its timestamp, `SourceLocation`, `ServiceContext`, redelivery marker and the `DeliveryTag` of the store that keeps it |
| `Destinations` | `Destination`, where batches of records are delivered; `ConsoleDestination`, which prints them; `InMemoryDestination`, which keeps the newest records it receives for the app or a test to read; `deliver(to:)`, which hands each batch of a sequence to every destination; `batch()`, the default batching; and the destination modifiers `accepting(_:)`, `redactingSensitiveValues()` and `droppingCallSite()` |
| `LoggingDestinations` | `LoggerDestination`: writes each event to a swift-log `Logger`, with its call site and context as metadata |
| `TracingDestinations` | `SpanEventDestination`: adds each event to the span that was active when it was tracked |
| `HTTPDestinations` | `HTTPDestination`: sends each batch to an HTTP endpoint as one request, its body written by a `BatchEncoder` and its first record's trace context in the header fields, through an `HTTPTransport`; `URLSessionTransport`, the default transport |
| `Trackers` | `Tracker`: records each tracked event as one of its `records`, writing it first to a store when it has one, and rejects one that breaks its declared constraints, reporting each as a `RejectionReport`; bound to a task with `withTracker` and read with `Tracker.current`; `Enricher`, which adds to each record's context, for every event or, through `enriched(by:)`, for those of one tracker copy; `Consent`, which delivers, holds or drops each event by its category's `ConsentStatus`, reporting every drop as a `ConsentDropReport`; and `Sampler`, which keeps a seeded fraction of events, or of the groups a context key's values make, at a `SampleRate`, stamping each kept record with its `SampleRateKey` and reporting each drop as a `SamplingDropReport` |
| `SwiftUITracking` | `EnvironmentValues.tracker`, set with `tracker(_:)` and shared with UIKit's `TrackerTrait`, and the view modifiers `trackOnAppear(_:)`, `trackOnTap(_:)`, `trackChange(of:_:)` and `trackScreen(_:)`, which tracks `ScreenViewed` and stamps the events tracked inside the screen with its `ScreenKey`; Apple platforms only, empty elsewhere |
| `UIKitTracking` | `TrackerTrait`: the tracker in a UIKit trait collection, set with `traitOverrides.tracker` on a window scene, view controller or view and read as `traitCollection.tracker`; and `UIControl.track(_:for:)`, which tracks an event through the tracker its control's traits hold when the action fires; iOS, iPadOS, tvOS, visionOS and Mac Catalyst only, empty elsewhere |
| `AppKitTracking` | `TrackerProviding`: a responder, window delegate or application delegate that holds a tracker; `NSView.tracker`, the tracker of the nearest one a view's actions reach; and `NSControl.track(_:)`, which tracks an event through it each time the control sends its action; macOS only, empty elsewhere |
| `AutomaticScreenTracking` | `trackScreensAutomatically(kinds:_:)`, on a `UIWindowScene` or an `NSWindow`: opt-in screen views, which track `ScreenViewed` through each screen's own tracker as its view controller appears, named after the controller or the SwiftUI view it hosts, renamed or skipped by a closure given each `DiscoveredScreen`, and left to a manual `trackScreen(_:)` where the screen has one; without swizzling; Apple platforms but watchOS, empty elsewhere |
| `AutomaticControlTracking` | `trackControlsAutomatically(_:)`, on a `UIWindowScene`: opt-in control activations, which track `ControlActivated` through each control's own tracker when a touch activates a UIKit control, named after its accessibility identifier and never its text, renamed or skipped by a closure given each `DiscoveredControl`, with its screen as `ScreenKey`; SwiftUI's controls left to `trackOnTap(_:)`; without swizzling; `ControlActivated` on every platform, the tracking iOS, iPadOS, tvOS, visionOS and Mac Catalyst only |
| `LifecycleTracking` | `trackLifecycle(kinds:version:versionStore:notificationCenter:)`, on a `Tracker`: opt-in lifecycle events, `ApplicationInstalled`, `ApplicationUpdated`, `ApplicationOpened`, `ApplicationBackgrounded` and `ApplicationTerminated`, from the platform's application notifications, installs and updates decided from the version a `VersionStore` keeps (`FileVersionStore`, `InMemoryVersionStore`); on backgrounding, the tracker's records made durable and `LifecycleBatchStrategy`'s batches flushed; each kind can be turned off; every platform, Linux tracking only its start and finish |
| `Sessions` | `Enricher.sessions(timeout:kinds:)`: opt-in sessions, an enricher that stamps every record's context with its `SessionKey`, a random UUID held in memory only, and starts a new session when an event comes after the timeout's inactivity, measured between the events' timestamps, tracking `SessionEnded(duration:)` and `SessionStarted` before it; each kind can be turned off while the key stays; `Sampler.sessions(where:rate:)`, which keeps or drops whole sessions; every platform |
| `StandardContext` | Opt-in enrichers of the context most analytics want: `Enricher.application()`, `device()`, `operatingSystem()`, `locale()`, `network()` and `vendorIdentifier()`, each setting its typed key (`ApplicationKey`, `DeviceKey`, `OperatingSystemKey`, `LocaleKey`, `NetworkKey`, `VendorIdentifierKey`); static values read once, as the enricher is made; the connection from an `NWPathMonitor` the enricher owns; the platform's `identifierForVendor`, sensitive, never stored or made up; every platform, the device, network and vendor identifier on Apple platforms only |
| `Checksums` | `CRC32`: the CRC-32 checksum of raw bytes |
| `Persistence` | `RecordStore`, where a tracker keeps each record until it is delivered; `SegmentStore`, the default, a size-bounded log of append-only segment files that reports every drop as a `DropReport`; and `BinaryCodable`, the binary encoding persisted events opt into |
| `GRDBPersistence` | `DatabaseStore`: a `RecordStore` that keeps records in a table of the app's own GRDB database, size-bounded, reporting every drop; Apple platforms only, and left out of `import Traffluent` |
| `EventMacros` | `@Event`: derives a struct's `Event` and `BinaryCodable` conformances, its name and its `EventSchema` from its declaration, checking the constraints `@Constrained` declares beside its properties; left out of `import Traffluent`, so only apps that use it build swift-syntax |
| `TrackingPlans` | `TrackingPlan`: the JSON Schema (draft 2020-12) of every event an app tracks, one document and one example per event and an index, exported from their `EventSchema` values; `TrackingPlanCheck`, its comparison with a committed plan, naming each `TrackingPlanDifference`; `TrackingPlanCommand`, the executable that writes or checks one, which the `export-tracking-plan` and `check-tracking-plan` command plugins run; left out of `import Traffluent` |
| `TrackingPlanTesting` | `expectTrackingPlan(_:matches:)`: records a Swift Testing issue with the check's report when the events no longer match the committed plan; for test targets, and left out of `import Traffluent` |
| `TrackerTesting` | `withRecordingTracker`: runs a test's body with a fresh tracker bound to its task, given to the body too, and returns a `TrackerRecording` of every event tracked in it, in order, typed with `events(of:)`; for test targets, and left out of `import Traffluent` |

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
