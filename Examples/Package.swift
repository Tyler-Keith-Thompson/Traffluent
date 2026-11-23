// swift-tools-version: 6.4
import PackageDescription

// The example apps, in their own package so the published library never depends on what they use
// (Hummingbird, ViewInspector). Run them with the `just example-*` recipes and test them with
// `just examples-test`; see Examples/README.md.

// Hand-written Bazel files sit beside the sources the Apple apps build (Examples/Apps/ExampleApp).
let bazelFiles = ["BUILD.bazel"]

func library(_ name: String) -> Target.Dependency {
    .product(name: name, package: "Traffluent")
}

let hummingbird: Target.Dependency = .product(name: "Hummingbird", package: "hummingbird")

func tracing(_ name: String) -> Target.Dependency {
    .product(name: name, package: "swift-distributed-tracing")
}

let targets: [Target] = [
    .target(name: "ExampleEvents", dependencies: [library("Events")], exclude: bazelFiles),
    .executableTarget(name: "CommandLineExample", dependencies: ["ExampleEvents", library("Destinations"), library("Trackers")]),
    .testTarget(name: "ExampleEventsTests", dependencies: ["ExampleEvents", library("Destinations"), library("Events"), library("Trackers")]),
    .target(name: "ExampleViews", dependencies: ["ExampleEvents", library("SwiftUITracking"), library("Trackers")], exclude: bazelFiles),
    .target(name: "ExampleServer", dependencies: ["ExampleEvents", library("Events"), library("HTTPDestinations"), library("Trackers"), hummingbird, .product(name: "HTTPTypes", package: "swift-http-types"), tracing("Instrumentation"), tracing("Tracing")]),
    .executableTarget(name: "ServerExample", dependencies: ["ExampleServer", "ExampleEvents", library("Destinations"), library("Trackers"), hummingbird, tracing("Tracing")]),
    .testTarget(name: "ExampleViewsTests", dependencies: [
        "ExampleViews", "ExampleEvents", library("Destinations"), library("Events"), library("SwiftUITracking"), library("Trackers"),
        tracing("Instrumentation"),
        .product(name: "ViewInspector", package: "viewinspector", condition: .when(platforms: [.macOS])),
    ]),
    // A store's events, declared with @Event, and the executable the export-tracking-plan plugin runs to
    // write their tracking plan into TrackingPlan/ and check-tracking-plan runs to check it; its test
    // checks it too.
    .target(name: "StoreEvents", dependencies: [library("EventMacros")]),
    .executableTarget(name: "StoreTrackingPlan", dependencies: ["StoreEvents", library("TrackingPlans")]),
    .testTarget(name: "StoreTrackingPlanTests", dependencies: ["StoreTrackingPlan", library("TrackingPlanTesting")]),
    .testTarget(name: "ExampleServerTests", dependencies: [
        "ExampleServer", "ExampleEvents", library("Destinations"), library("Events"), library("HTTPDestinations"), library("Trackers"),
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
        .package(url: "https://github.com/hummingbird-project/hummingbird", from: "2.29.0"),
        // The server example's tracer, which joins each batch's request to the app's trace.
        .package(url: "https://github.com/apple/swift-distributed-tracing", from: "1.7.4"),
        .package(url: "https://github.com/apple/swift-http-types", from: "1.8.0"),
        // 0.x: its minor releases may break its API.
        .package(url: "https://github.com/nalexn/ViewInspector", .upToNextMinor(from: "0.10.5")),
    ],
    targets: targets
)
