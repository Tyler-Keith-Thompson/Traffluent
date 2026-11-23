# Examples

Example apps for every platform Traffluent supports, as a SwiftPM package that depends on the
library by path (`..`). Each builds a `Tracker` at its composition root, delivers its records to a
`ConsoleDestination`, and tracks typed events from `ExampleEvents`.

| Path | What it is |
|---|---|
| `Sources/ExampleEvents` | `AppLaunched(platform:)`, `ButtonTapped(label:)`, `RequestServed(path:status:)`, `Platform` |
| `Sources/ExampleViews` | `ExampleView`, the SwiftUI screen the Apple apps share |
| `Sources/ExampleServer` | The Hummingbird routes, `RequestTrackingMiddleware`, and `POST /batches`, which accepts `HTTPDestination` batches (`EventNamesEncoder`) in a server span joined to the app's trace |
| `Sources/CommandLineExample` | The Linux program |
| `Sources/ServerExample` | The server, on 127.0.0.1:8080 |
| `Apps/ExampleApp` | The Apple app: one `@main` source; Bazel applications for iPhone and iPad, Mac, visionOS and watchOS |
| `scripts/catalyst_app.py` | The same app built for Mac Catalyst |

SwiftPM builds and tests the package (`just examples-test`). The Apple apps need application
bundles, which SwiftPM doesn't make, so Bazel builds them from the hand-written `BUILD.bazel` files
here; every one of those targets is `manual`, so the library's `bazel test //...` leaves them out.
The root README's "Examples" section lists each build command.
