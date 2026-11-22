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
await pipeline.track(SignedUp(plan: "pro"))  // prints: SignedUp SignedUp(plan: "pro")
```

## Modules

| Module | Holds |
|---|---|
| `Events` | `Event`: the protocol typed analytics events conform to |
| `Destinations` | `Destination`, where events are delivered, and `ConsoleDestination`, which prints them |
| `Pipelines` | `Pipeline`: delivers each tracked event to every destination |

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
