# Examples

Example apps for every platform Traffluent supports, as a SwiftPM package that depends on the
library by path (`..`). Each builds a `Tracker` at its composition root, delivers its records to a
`ConsoleDestination`, and tracks typed events from `ExampleEvents`.

| Path | What it is |
|---|---|
| `Sources/ExampleEvents` | `AppLaunched(platform:)`, `ButtonTapped(label:)`, `RequestServed(path:status:)`, `Platform` |
| `Sources/ExampleViews` | `ExampleView`, the SwiftUI screen the Apple apps share, which tracks through the tracker in its environment (`SwiftUITracking`) |
| `Sources/ExampleServer` | The Hummingbird routes, `RequestTrackingMiddleware`, and `POST /batches`, which accepts `HTTPDestination` batches (`RecordLinesEncoder`, a record's identifier and event name per line) in a server span joined to the app's trace |
| `Sources/CommandLineExample` | The Linux program |
| `Sources/ServerExample` | The server, on 127.0.0.1:8080 |
| `Apps/ExampleApp` | The Apple app: one `@main` source, which sets the tracker at the root of its views and places `ExampleView` as the screen "Home"; Bazel applications for iPhone and iPad, Mac, visionOS and watchOS |
| `scripts/catalyst_app.py` | The same app built for Mac Catalyst |
| `Sources/StoreEvents` | `CheckoutStarted`, `OrderCompleted` and `SignedUp`, a store's events declared with `@Event` |
| `Sources/StoreTrackingPlan` | The `TrackingPlanCommand` that lists them, which `export-tracking-plan` and `check-tracking-plan` run |
| `Tests/StoreTrackingPlanTests` | A test that fails when the events no longer match their committed plan (`expectTrackingPlan`) |
| `TrackingPlan` | Their tracking plan, as the plugin writes it, with each event's example: `just example-tracking-plan` checks it, writes it again and fails if it changed |

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
| `just examples` | Every example above, then `just examples-test` |
| `just example-tracking-plan` | Checks the store's events against `TrackingPlan`, writes it again and fails if it changed |

`just generate` gives each Apple app a scheme in the Xcode project.
