# Getting Started

Add Traffluent to an app, declare its events, deliver them to a server and test what the app tracks.

## Overview

This walkthrough builds the analytics of a small store app, one step at a time. The code comes
from the store app in the package's
[`Examples`](https://github.com/Tyler-Keith-Thompson/Traffluent/tree/main/Examples), cut down
where the app does more than a step needs. Run that app to see every step working together
(`Examples/README.md` says how). Each step links to the guide that covers it in full.

### Add the package

Add Traffluent to your package's dependencies:

```swift
dependencies: [
    .package(url: "https://github.com/Tyler-Keith-Thompson/Traffluent", from: "0.0.37"),
],
```

Then add products to your targets. `Traffluent` imports almost every module. `TrackingPlans`,
which the delivery below needs, and `TrackerTesting`, for tests, are products of their own:

```swift
.target(name: "MyApp", dependencies: [
    .product(name: "Traffluent", package: "Traffluent"),
    .product(name: "TrackingPlans", package: "Traffluent"),
]),
.testTarget(name: "MyAppTests", dependencies: [
    "MyApp",
    .product(name: "TrackerTesting", package: "Traffluent"),
]),
```

### Declare the events

Declare each event as a struct marked `@Event`, with a fixed name, which is what servers and
stored records know it by. A property can carry constraints the tracker checks before anything
else, and a personal value is `Sensitive`, which a destination can leave out with
`redactingSensitiveValues()`:

```swift
import Traffluent

@Event(name: "product_added_to_cart")
struct ProductAddedToCart: Equatable {
    @Constrained(.pattern("^[a-z0-9]+(-[a-z0-9]+)*$", example: "canvas-tote"))
    var productID: String
    @Constrained(.minimum(1), .maximum(10))
    var quantity: Int
}

@Event(name: "signed_up", consent: .functional)
struct SignedUp {
    var plan: String
    var email: Sensitive<String>?
    var referrer: String?
}
```

A `ProductAddedToCart` with a quantity of 0 is rejected and never delivered. `SignedUp` is
collected for the `functional` consent category; events are `analytics` unless they say otherwise.
Its email address is optional, so a record whose email a destination left out still matches the
tracking plan. The store app declares its events in a module of their own, `StoreEvents`. See
<doc:DefiningEvents>.

### Build the tracker

Build one tracker where the app starts. A `SegmentStore` keeps each record on disk until it is
delivered, so events tracked just before the app ends are sent on the next launch. A `Consent`
holds each event until the user grants its category. The enrichers stamp every event with its
session and with the app, device, operating system, locale and network it was tracked on:

```swift
let consent = Consent(savedDecisions)
let store = try SegmentStore(events: [
    ProductAddedToCart.self,
    SignedUp.self,
    ScreenViewed.self,
    SessionStarted.self,
    SessionEnded.self,
])
let tracker = Tracker(
    store: store,
    consent: consent,
    enrichers: [.sessions(timeout: .seconds(30 * 60)), .application(), .device(), .operatingSystem(), .locale(), .network()]
)
```

`Consent` keeps decisions in memory only. `savedDecisions` is what the user chose at an earlier
launch, which the app saved (the store app's `ConsentPreferences` saves them to a file). The store
lists the events the library tracks for the app too: screen views and the sessions' start and end.
See <doc:PersistingRecords>, <doc:ConsentGating> and <doc:SessionsAndStandardContext>.

### Make the tracker reachable

Code that runs inside a task can read the tracker bound with `withTracker`:

```swift
withTracker(tracker) {
    Tracker.current.track(SignedUp(plan: "plus", email: Sensitive("ada@example.com"), referrer: nil))
}
```

The binding doesn't reach callbacks that a framework runs itself, such as a SwiftUI button's
action. Views read the tracker from the environment instead, so set it at the root of the views,
in your `App`'s body:

```swift
WindowGroup {
    StoreView()
        .tracker(tracker)
}
```

The store app also turns on lifecycle tracking as it launches, which tracks opens and moves to the
background (<doc:AutomaticTracking>). See <doc:TrackingEvents> and <doc:TrackingFromViews>.

### Track from code and from views

Code that changes something worth tracking takes the tracker it tracks through. The store's cart
tracks `ProductAddedToCart` as a product goes in, and throws before tracking anything when the
quantity is out of range:

```swift
struct Product: Identifiable, Hashable {
    var id: String
    var name: String
    var priceInCents: Int

    static let catalog = [
        Product(id: "canvas-tote", name: "Canvas Tote", priceInCents: 2_400),
        Product(id: "enamel-mug", name: "Enamel Mug", priceInCents: 1_800),
    ]
}

struct QuantityOutOfRange: Error, Equatable {}

struct Cart {
    struct Line: Equatable {
        var product: Product
        var quantity: Int
    }

    private(set) var lines: [Line] = []

    static let quantities = 1...10

    mutating func add(_ product: Product, quantity: Int = 1, trackingWith tracker: Tracker) throws(QuantityOutOfRange) {
        guard Self.quantities.contains(quantity) else { throw QuantityOutOfRange() }
        lines.append(Line(product: product, quantity: quantity))
        tracker.track(ProductAddedToCart(productID: product.id, quantity: quantity))
    }
}
```

A view reads the tracker from the environment and hands it to the cart. `trackScreen(_:)`, applied
where a screen's view is placed, tracks `ScreenViewed` each time it appears and stamps the events
tracked inside it with the screen's name:

```swift
struct StoreView: View {
    @State private var cart = Cart()

    var body: some View {
        NavigationStack {
            List(Product.catalog) { product in
                NavigationLink(product.name) {
                    ProductView(product: product, cart: $cart)
                        .trackScreen("Product")
                }
            }
            .trackScreen("Catalog")
        }
    }
}

struct ProductView: View {
    let product: Product
    @Binding var cart: Cart
    @Environment(\.tracker) private var tracker

    var body: some View {
        Button("Add to Cart") {
            // The default quantity, 1, is in range, so the cart never refuses it.
            try? cart.add(product, trackingWith: tracker)
        }
        .navigationTitle(product.name)
    }
}
```

UIKit and AppKit find the tracker through a trait and the responder chain. See
<doc:TrackingFromViews>, and <doc:AutomaticTracking> for screens and controls that track
themselves.

### Deliver to a server

A delivery batches the tracker's records and hands each batch to its destinations. To send them
to a TraffluentCollector, deliver to an `HTTPDestination` with a `CollectorBatchEncoder`, which
writes each record's properties through the event's schema in a `TrackingPlan`. The plan lists
every event the tracker can see, the library's included. `redactingSensitiveValues()` keeps the
email address off this destination:

```swift
import TrackingPlans

let plan = TrackingPlan(schemas: [
    ProductAddedToCart.schema,
    SignedUp.schema,
    ScreenViewed.schema,
    SessionStarted.schema,
    SessionEnded.schema,
])
let collector = HTTPDestination(
    endpoint: collectorURL,
    headerFields: [.authorization: "Bearer \(apiKey)"],
    encoder: CollectorBatchEncoder(plan: plan))
let (bufferDrops, bufferDropReporter) = AsyncStream.makeStream(of: BufferDropReport.self)
let delivery = tracker.records
    .batch()
    .deliver(to: collector.redactingSensitiveValues(), bufferDropReporter: bufferDropReporter)
let delivering = Task { try await delivery.execute() }
```

`batch()` sends 20 records at a time, or every 30 seconds while any are waiting. Nothing runs until
`execute()`, and the delivery runs for as long as the tracker does, so start it once and keep the
task if the app needs to stop it. A send that gets no response, a 5xx, 408 or 429 is sent again with backoff
until it arrives, and the store keeps its records meanwhile. To send to PostHog instead, give the
destination a `PostHogBatchEncoder` (module ``/PostHogEncoding``). See <doc:ChoosingDestinations>.

### Watch what is dropped

Each event that doesn't reach the server shows up in a report. The tracker reports a broken
constraint, the consent a denied category, the store a record it couldn't keep, the destination a
batch the server refused, and the delivery a batch its full buffer dropped. Read every report in
one task:

```swift
let rejections = tracker.rejectionReports
let consentDrops = consent.dropReports
let storeDrops = store.dropReports
let collectorDrops = collector.dropReports
Task {
    await withDiscardingTaskGroup { group in
        group.addTask { for await report in rejections { print("Rejected: \(report)") } }
        group.addTask { for await report in consentDrops { print("Not consented: \(report)") } }
        group.addTask { for await report in storeDrops { print("Not stored: \(report)") } }
        group.addTask { for await report in collectorDrops { print("Not sent: \(report)") } }
        group.addTask { for await report in bufferDrops { print("Buffer full: \(report)") } }
    }
}
```

Each stream has one reader. The task reads the streams, not their owners, so it keeps no store or
destination alive. The store app merges them into one stream of its own type, `AnalyticsDrop`, and
logs each one.

### Export and check the tracking plan

The tracking plan is a JSON Schema document for each event, committed beside the code, that the
people and services reading the events can review. A small executable that lists the plan above
writes it, and a check fails when the events no longer match it:

```sh
swift package --allow-writing-to-package-directory export-tracking-plan
swift package check-tracking-plan
```

See <doc:TrackingPlanWorkflow> for the executable, the check from a test and catching breaking
changes in CI.

### Test what the code tracks

`withRecordingTracker` runs a test's body with a fresh tracker and returns what it tracked, so
tests running at the same time never see each other's events:

```swift
import Testing
import TrackerTesting

@Test("Adding a product tracks ProductAddedToCart with its identifier and the quantity")
func add() async throws {
    let tote = Product(id: "canvas-tote", name: "Canvas Tote", priceInCents: 2_400)
    var sut = Cart()
    let expectedEvents = [ProductAddedToCart(productID: "canvas-tote", quantity: 2)]
    let expectedLines = [Cart.Line(product: tote, quantity: 2)]

    let tracked = try await withRecordingTracker { tracker in
        try sut.add(tote, quantity: 2, trackingWith: tracker)
    }

    #expect(tracked.events(of: ProductAddedToCart.self) == expectedEvents)
    #expect(sut.lines == expectedLines)
}
```

See <doc:TestingWhatYouTrack>.
