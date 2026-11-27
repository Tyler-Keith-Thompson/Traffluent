# ``Traffluent``

Typed analytics events for Swift, delivered in batches to any number of destinations.

## Overview

Each event is a struct, so the compiler checks its name and every property. A tracker holds back
the events the user hasn't consented to, stamps the rest with their session and device, keeps them
on disk and delivers them to your server, sending again when the network or the server fails.

### An app's analytics, from launch

Declare the events. The tracker rejects an event that breaks a constraint before it is stored or
delivered, and a `Sensitive` value reaches only the destinations that don't redact it:

```swift
import SwiftUI
import Traffluent
import TrackingPlans

@Event(name: "product_added_to_cart")
struct ProductAddedToCart {
    var productID: String
    @Constrained(.minimum(1), .maximum(10))
    var quantity: Int
}

@Event(name: "signed_up")
struct SignedUp {
    var plan: String
    var email: Sensitive<String>
}
```

Build the tracker and start its delivery once, as the app launches:

```swift
func startAnalytics(consent: Consent) throws -> Tracker {
    let plan = try TrackingPlan(schemas: [
        ProductAddedToCart.schema, SignedUp.schema, SessionStarted.schema, SessionEnded.schema,
    ])
    // Records wait on disk until they are delivered, across launches.
    let store = try SegmentStore(events: [
        ProductAddedToCart.self, SignedUp.self, SessionStarted.self, SessionEnded.self,
    ])
    // Every event gets its session, and the app, device, OS, locale and network it was tracked on.
    let tracker = Tracker(
        store: store,
        consent: consent,
        enrichers: [.sessions(), .application(), .device(), .operatingSystem(), .locale(), .network()])

    let collector = HTTPDestination(
        endpoint: collectorURL,
        headerFields: [.authorization: "Bearer \(apiKey)"],
        encoder: CollectorBatchEncoder(plan: plan))
    // Analytics events only, without their email addresses, 20 at a time or every 30 seconds.
    let delivery = tracker.records.batch().deliver(
        to: collector.accepting(.analytics).redactingSensitiveValues())
    Task {
        do {
            try await delivery.execute()  // for the life of the app
        } catch {
            print("Delivery stopped: \(error)")
        }
    }

    // Every event that won't arrive, and why.
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
        }
    }
    return tracker
}
```

Then make the tracker the app's default and hand it to the views, which track through it:

```swift
@main
struct StoreApp: App {
    let tracker: Tracker

    init() {
        do {
            // The user's earlier decisions, which the app saved; undecided categories wait in memory.
            let tracker = try startAnalytics(consent: Consent(savedDecisions))
            // `Tracker.current` falls back to it where nothing else reaches, such as a detached task.
            try Tracker.bootstrap(tracker)
            self.tracker = tracker
        } catch {
            print("Analytics are off: \(error)")
            tracker = .noOp
        }
    }

    var body: some Scene {
        WindowGroup {
            CartView()
                .tracker(tracker)
        }
    }
}

struct CartView: View {
    @Environment(\.tracker) private var tracker

    var body: some View {
        Button("Add to Cart") {
            tracker.track(ProductAddedToCart(productID: "canvas-tote", quantity: 1))
        }
    }
}
```

`import Traffluent` imports every module except ``/TrackingPlans``, ``/PostHogEncoding``, ``/PropertyJSON``,
``/GRDBPersistence`` and the testing modules, which are products of their own.

### Where to go next

- Set it up step by step, from adding the package to testing what you track: <doc:GettingStarted>.
- Declare events and their constraints: <doc:DefiningEvents>; change one that has shipped:
  <doc:ChangingEvents>.
- Track from SwiftUI, UIKit and AppKit views: <doc:TrackingFromViews>; let screens, controls and
  the app's lifecycle track themselves: <doc:AutomaticTracking>.
- Reach the tracker from any code, batch records and add context to them: <doc:TrackingEvents>.
- Keep events when the app ends or goes offline before delivering them: <doc:PersistingRecords>.
- Ask for consent and gate events by it: <doc:ConsentGating>.
- Keep a fraction of events or sessions: <doc:SamplingEvents>.
- Group events into sessions and stamp them with the app and device: <doc:SessionsAndStandardContext>.
  A session's key is a UUIDv7, its start time in Unix milliseconds followed by random bits, held in
  memory only.
- Export the events' schemas and catch breaking changes in CI: <doc:TrackingPlanWorkflow>.
- Test what your code tracks: <doc:TestingWhatYouTrack>.
- Send to logs, traces, your own server, PostHog or memory, with values for one destination
  alone: <doc:ChoosingDestinations>.
- Send to an analytics vendor not yet covered, from a module of your own: <doc:WritingAVendorDestination>.
- Decide what belongs in an event and what stays out of it: <doc:WhatGoesWhere>, <doc:IdentifyingPeople>
  and <doc:PrivacyManifests>.

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:TrackingEvents>
- <doc:ChoosingDestinations>
- <doc:TrackingFromViews>
- <doc:TestingWhatYouTrack>

### Guides

- <doc:AutomaticTracking>
- <doc:SessionsAndStandardContext>
- <doc:SamplingEvents>
- <doc:ConsentGating>
- <doc:PersistingRecords>
- <doc:DefiningEvents>
- <doc:TrackingPlanWorkflow>
- <doc:WritingAVendorDestination>

### Choosing what to record

- <doc:WhatGoesWhere>
- <doc:ChangingEvents>
- <doc:IdentifyingPeople>
- <doc:PrivacyManifests>

### Modules

- ``/Events``
- ``/Trackers``
- ``/SwiftUITracking``
- ``/UIKitTracking``
- ``/AppKitTracking``
- ``/AutomaticScreenTracking``
- ``/AutomaticControlTracking``
- ``/LifecycleTracking``
- ``/Sessions``
- ``/StandardContext``
- ``/Destinations``
- ``/LoggingDestinations``
- ``/TracingDestinations``
- ``/HTTPDestinations``
- ``/CollectorEncoding``
- ``/PostHogEncoding``
- ``/PropertyJSON``
- ``/Persistence``
- ``/GRDBPersistence``
- ``/EventMacros``
- ``/TrackingPlans``
- ``/AsyncQueues``
- ``/Checksums``

### Testing

- ``/TrackingPlanTesting``
- ``/TrackerTesting``
- ``/DestinationTesting``
