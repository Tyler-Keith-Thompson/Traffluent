# Traffluent

Traffluent is an analytics library for Swift whose events are types, so the compiler checks every
name and property. It batches events, keeps them on disk and delivers them to the destinations you
choose, sending again until they arrive. It holds back what the user hasn't consented to and
redacts sensitive values, on Apple platforms and Linux.

## Installation

```swift
.package(url: "https://github.com/Tyler-Keith-Thompson/Traffluent", from: "0.0.1"),
```

Add the `Traffluent` product to your target, and `TrackingPlans` for the plan below. Traffluent
requires Swift 6.4 and supports macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2 and Linux.

## Quick start

```swift
import Traffluent
import TrackingPlans

@Event(name: "product_added_to_cart")
struct ProductAddedToCart {
    var productID: String
    @Constrained(.minimum(1), .maximum(10))
    var quantity: Int
}

func startAnalytics() throws {
    let plan = try TrackingPlan(
        schemas: [ProductAddedToCart.schema, SessionStarted.schema, SessionEnded.schema])
    // Every event gets its session, and the app, device, OS, locale and network it was tracked on.
    let tracker = Tracker(
        enrichers: [.sessions(), .application(), .device(), .operatingSystem(), .locale(), .network()])
    let collector = HTTPDestination(
        endpoint: collectorURL,
        headerFields: [.authorization: "Bearer \(apiKey)"],
        encoder: CollectorBatchEncoder(plan: plan))
    // Analytics events only, with sensitive values left out, 20 at a time or every 30 seconds.
    let delivery = tracker.records.batch().deliver(
        to: collector.accepting(.analytics).redactingSensitiveValues())
    Task { try? await delivery.execute() }  // for the life of the app
    try Tracker.bootstrap(tracker)  // what `Tracker.current` falls back to, anywhere in the app
}

// Once, as the app launches; then track from any code.
try startAnalytics()
Tracker.current.track(ProductAddedToCart(productID: "canvas-tote", quantity: 1))
```

## Next steps

- [Getting Started](https://tyler-keith-thompson.github.io/Traffluent/documentation/traffluent/gettingstarted): from adding the package to testing what you track, step by step
- [Track from SwiftUI, UIKit and AppKit](https://tyler-keith-thompson.github.io/Traffluent/documentation/traffluent/trackingfromviews)
- [Keep events when the app goes offline or quits](https://tyler-keith-thompson.github.io/Traffluent/documentation/traffluent/persistingrecords)
- [Ask for consent and gate events by it](https://tyler-keith-thompson.github.io/Traffluent/documentation/traffluent/consentgating)
- [Send to PostHog, your own server, logs or traces](https://tyler-keith-thompson.github.io/Traffluent/documentation/traffluent/choosingdestinations)
- [Write a destination for another analytics vendor](https://tyler-keith-thompson.github.io/Traffluent/documentation/traffluent/writingavendordestination)
- [Catch breaking event changes in CI](https://tyler-keith-thompson.github.io/Traffluent/documentation/traffluent/trackingplanworkflow)

The [documentation](https://tyler-keith-thompson.github.io/Traffluent/documentation/traffluent)
lists every guide and module, and [`Examples/`](Examples) holds a store app for each platform, a
command-line tool and a server. Traffluent is licensed under Apache 2.0 (`LICENSE`).
