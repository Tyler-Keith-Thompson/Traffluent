# Examples

A small store app built on Traffluent, with the server it sends its events to and a command-line
run of the same analytics. It is a SwiftPM package of its own that depends on the library by path
(`..`). The shopper browses products, adds them to a cart, taps a promotion, checks out, signs up,
and chooses what the store may collect.

## Reading the app

Read the app's code in this order, which is the order it builds up in:

1. `Sources/StoreEvents` declares the events with `@Event`, each with a fixed wire name.
   `ProductAddedToCart` constrains its product identifier to a pattern and its quantity to 1
   through 10. `SignedUp` is collected for the `functional` category. Its email address is an
   optional `Sensitive` value, so a record whose email a destination redacted still matches the
   plan. `PromotionTapped` is collected for `advertising`.
2. `Sources/StoreModel` is the store itself: `Product`, `Promotion`, `Cart`, `Order` and
   `Account`. Each change that matters to analytics tracks through `Tracker.current`
   (`try cart.add(product, quantity: 2)`): the app's tracker, which the app bootstraps, or the one
   a test binds with `withRecordingTracker { try cart.add(product, quantity: 2) }` and reads what was
   tracked from. A quantity outside 1 through 10 throws `QuantityOutOfRange` before anything is
   tracked.
3. `Sources/StoreAnalytics` builds the pipeline. `StoreAnalytics` keeps records in a `SegmentStore`,
   gates them with the shopper's `Consent`, adds sessions and standard context
   (`StoreAnalytics.enrichers`), and delivers batches to an `HTTPDestination` with
   `CollectorBatchEncoder` and `redactingSensitiveValues()`. Its `drops` stream merges every drop
   report: rejections, consent, the store, the collector and the delivery's buffer.
   `ConsentPreferences` saves the shopper's decisions and restores them at launch.
   `TrackingPlan.store` lists every event the app tracks, the library's included.
4. `Sources/StoreViews` holds the SwiftUI screens. Each reads the tracker from the environment and
   is placed with `trackScreen(_:)`. A tracker set for a view tree with `.tracker(_:)`, such as the
   one `trackScreen(_:)` adds the screen's name to or a preview's, doesn't reach code that reads
   `Tracker.current`, so a view binds it around each change to the cart or the account
   (`withTracker(tracker) { cart.startCheckout() }`), and the event carries the screen's name.
   `ConsentPrompt` grants or denies every category, and `ConsentToggle` in the account screen does
   it one category at a time. The checkout is a UIKit view controller where UIKit has window
   scenes, and `trackWindowSceneAutomatically(_:)` turns on automatic screen and control tracking
   there. On the Mac and the watch it is a SwiftUI view that tracks the same events with
   `trackOnTap(_:)` and `trackChange(of:_:)`.
5. `Apps/ExampleApp/StoreApp.swift` is the composition root. It restores consent, builds
   `StoreAnalytics`, makes its tracker the process's default (`Tracker.bootstrap`), keeps the
   `LifecycleObservation` from `trackLifecycle`, starts the delivery, logs every drop, and sets the
   tracker at the root of the views.

## Running it

Start the server with `just serve-example`, then run the app from Xcode (`just generate`) or build
it with a recipe below. The app sends its batches to `http://127.0.0.1:8080/v1/batches`, where the
server's stand-in collector logs each record it receives. Without the server, the app keeps its
records on disk and retries until the server answers.

| Path | What it is |
|---|---|
| `Sources/ExampleServer` | The Hummingbird routes: `POST /v1/batches`, which reads collector batches in a server span joined to the app's trace, and routes that track their own requests (`RequestServed`, `RequestTrackingMiddleware`) |
| `Sources/ServerExample` | The server, on 127.0.0.1:8080 |
| `Sources/CommandLineExample` | A scripted shopping trip through `StoreAnalytics` on any platform, Linux included, printing each batch's body in place of sending it |
| `Sources/StoreTrackingPlan` | The `TrackingPlanCommand` that `export-tracking-plan` and `check-tracking-plan` run |
| `TrackingPlan` | The tracking plan as the plugin writes it, with each event's example |
| `Apps/ExampleApp` | The Apple app's source and its Bazel applications for iPhone and iPad, Mac, visionOS and watchOS |
| `scripts/catalyst_app.py` | The same app built for Mac Catalyst |
| `Tests/StoreViewsSimulatorTests` | The UIKit checkout's automatic tracking, in the iOS simulator: its screen view and its order say `Checkout` |

SwiftPM builds and tests the package (`just examples-test`). The Apple apps need application
bundles, which SwiftPM doesn't make, so Bazel builds them from the hand-written `BUILD.bazel` files
here. Every one of those targets is `manual`, so the library's `bazel test //...` leaves them out;
the recipes name them:

| Recipe | Builds |
|---|---|
| `just example-ios` | The iPhone and iPad app, for the simulator |
| `just example-mac` | The Mac app |
| `just example-catalyst` | The iOS app for Mac Catalyst, which rules_apple has no rule for (`scripts/catalyst_app.py`) |
| `just example-visionos` | The visionOS app, for the simulator |
| `just example-watchos` | The watchOS app, for the simulator |
| `just example-linux` | The command-line and server examples on Linux, in Docker, then runs the command-line one |
| `just example-server` | The server; `just serve-example` runs it on 127.0.0.1:8080 |
| `just example-ios-test` | Runs `Tests/StoreViewsSimulatorTests` in the iOS simulator, inside the library's test host (`tools/test_host`), which gives windows a scene |
| `just examples` | Every example above, then `just examples-test` |
| `just example-tracking-plan` | Checks the app's events against `TrackingPlan`, writes it again and fails if it changed |

Change an event and `just example-tracking-plan` fails until you write the plan again with
`swift package --allow-writing-to-package-directory export-tracking-plan` from `Examples/` and
commit it with the change.
