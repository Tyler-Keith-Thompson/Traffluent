// swift-tools-version: 6.4
import PackageDescription

// The example apps, in their own package so the published library never depends on what they use
// (Hummingbird, ViewInspector). Run them with the `just example-*` recipes and test them with
// `just examples-test`; see Examples/README.md.

// `just example-wasm` sets this: WebAssembly has no sockets for Hummingbird (SwiftNIO's NIOPosix
// doesn't build for WASI), and resolving it there needs an older Xcode for swiftly's toolchain, so
// the package then declares only what the command-line example needs.
let wasm = Context.environment["TRAFFLUENT_EXAMPLES_WASM"] != nil

// Hand-written Bazel files sit beside the sources the Apple apps build (Examples/Apps/ExampleApp).
let bazelFiles = ["BUILD.bazel"]

func library(_ name: String) -> Target.Dependency {
    .product(name: name, package: "Traffluent")
}

let hummingbird: Target.Dependency = .product(name: "Hummingbird", package: "hummingbird")

func tracing(_ name: String) -> Target.Dependency {
    .product(name: name, package: "swift-distributed-tracing")
}

let portable: [Target] = [
    .target(name: "ExampleEvents", dependencies: [library("Events")], exclude: bazelFiles),
    .executableTarget(name: "CommandLineExample", dependencies: ["ExampleEvents", library("Destinations"), library("Trackers")]),
    .testTarget(name: "ExampleEventsTests", dependencies: ["ExampleEvents", library("DestinationTesting"), library("Destinations"), library("Events"), library("Trackers")]),
]

let rest: [Target] = [
    .target(name: "ExampleViews", dependencies: ["ExampleEvents", library("Trackers")], exclude: bazelFiles),
    .target(name: "ExampleServer", dependencies: ["ExampleEvents", library("Events"), library("HTTPDestinations"), library("Trackers"), hummingbird, .product(name: "HTTPTypes", package: "swift-http-types"), tracing("Instrumentation"), tracing("Tracing")]),
    .executableTarget(name: "ServerExample", dependencies: ["ExampleServer", "ExampleEvents", library("DestinationTesting"), library("Destinations"), library("Trackers"), hummingbird, tracing("Tracing")]),
    .testTarget(name: "ExampleViewsTests", dependencies: [
        "ExampleViews", "ExampleEvents", library("DestinationTesting"), library("Destinations"), library("Events"), library("Trackers"),
        .product(name: "ViewInspector", package: "viewinspector", condition: .when(platforms: [.macOS])),
    ]),
    .testTarget(name: "ExampleServerTests", dependencies: [
        "ExampleServer", "ExampleEvents", library("DestinationTesting"), library("Destinations"), library("Events"), library("HTTPDestinations"), library("Trackers"),
        hummingbird, .product(name: "HummingbirdTesting", package: "hummingbird"),
        tracing("Instrumentation"), tracing("Tracing"), tracing("InMemoryTracing"),
    ]),
]

let package = Package(
    name: "TraffluentExamples",
    platforms: [.macOS(.v15), .iOS(.v18), .tvOS(.v18), .watchOS(.v11), .visionOS(.v2)],
    dependencies: [
        // Named, so the identity does not depend on the checkout directory's name.
        .package(name: "Traffluent", path: ".."),
    ] + (wasm ? [] : [
        .package(url: "https://github.com/hummingbird-project/hummingbird", from: "2.29.0"),
        // The server example's tracer, which joins each batch's request to the app's trace.
        .package(url: "https://github.com/apple/swift-distributed-tracing", from: "1.7.4"),
        .package(url: "https://github.com/apple/swift-http-types", from: "1.8.0"),
        // 0.x: its minor releases may break its API.
        .package(url: "https://github.com/nalexn/ViewInspector", .upToNextMinor(from: "0.10.5")),
    ]),
    targets: portable + (wasm ? [] : rest)
)
