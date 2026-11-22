# Traffluent

Traffluent is an analytics library for Swift that isn't tied to a vendor. Events are strongly
typed values, not stringly typed names with `[String: Any]` property bags. One pipeline fans
each event out to as many destinations as you like. It also handles what thin wrappers skip:
batching, on-disk persistence, retry, consent gating, schema enforcement and automatic
instrumentation. It is built for Swift 6 strict concurrency, has no singletons, and runs on every
platform Swift does, not only Apple's. Use it in place of the in-house typed event layer most
large apps end up writing, with vendor SDKs as plain sinks.

[Documentation](https://tyler-keith-thompson.github.io/Traffluent/documentation/)

## Installation

Traffluent requires Swift 6.3 and supports macOS 15, iOS 18, tvOS 18, watchOS 11 and visionOS 2
or later.

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
    // .product(name: "Pipelines", package: "Traffluent"),
]),
```

## Usage

Every example here is a test in `Tests/TraffluentTests`, so it cannot drift from the code.

```swift
import Traffluent

struct SignedUp: Event {
    var plan: String
}

let pipeline = Pipeline(ConsoleDestination())
pipeline.track(SignedUp(plan: "pro"))
pipeline.finish()
try await pipeline.run().execute()  // prints: SignedUp SignedUp(plan: "pro")
```

`track` returns at once. It records the event as an `EventRecord`, with the time it was tracked
and the caller's file, module, function, line and column, and sends the record into the
pipeline. `run()` is the work of delivering: it gathers records into batches and hands each batch
to every destination. Run it for as long as the app tracks events; `finish()` delivers what is
still pending and ends it. By default a batch goes out every 20 events, or every 30 seconds while
any are waiting; pass `strategy:` to choose another, such as `.count(100)` or
`.either(.count(50), .time(interval: .seconds(10), clock: ContinuousClock()))`. Timestamps and
the default strategy's timer read the pipeline's `clock:`, a `ContinuousClock` unless you pass
another (a test clock in tests).

## Modules

| Module | Holds |
|---|---|
| `Events` | `Event`: the protocol typed analytics events conform to, and `EventRecord`: a tracked event with its timestamp and `SourceLocation` |
| `Destinations` | `Destination`, where batches of records are delivered, and `ConsoleDestination`, which prints them |
| `Pipelines` | `Pipeline`: records each tracked event, batches the records and delivers every batch to every destination |

## Examples

Small apps that send typed events through a `Pipeline` to a `ConsoleDestination`, one per
platform. Each builds its pipeline where it starts and passes it down. They live in
[`Examples/`](Examples), a package of their own that depends on this one.

| Platform | Example | Build |
|---|---|---|
| iPhone and iPad | [`Examples/Apps/ExampleApp`](Examples/Apps/ExampleApp), one universal app | `just example-ios` |
| Mac | [`Examples/Apps/ExampleApp`](Examples/Apps/ExampleApp) | `just example-mac` |
| Mac Catalyst | [`Examples/Apps/ExampleApp`](Examples/Apps/ExampleApp), the iOS app built for the Mac | `just example-catalyst` |
| visionOS | [`Examples/Apps/ExampleApp`](Examples/Apps/ExampleApp) | `just example-visionos` |
| watchOS | [`Examples/Apps/ExampleApp`](Examples/Apps/ExampleApp) | `just example-watchos` |
| Linux | [`Examples/Sources/CommandLineExample`](Examples/Sources/CommandLineExample) | `just example-linux` (Docker) |
| Wasm | [`Examples/Sources/CommandLineExample`](Examples/Sources/CommandLineExample) | `just example-wasm` (wasmtime) |
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
