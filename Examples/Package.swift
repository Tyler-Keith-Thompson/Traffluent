// swift-tools-version: 6.4
import PackageDescription

// The example store app, its server and its command-line run, in their own package so the
// published library never depends on what they use (Hummingbird, ViewInspector). Run them with
// the `just example-*` recipes and test them with `just examples-test`; see Examples/README.md.

// Hand-written Bazel files sit beside the sources the Apple apps build (Examples/Apps/ExampleApp).
let bazelFiles = ["BUILD.bazel"]

func library(_ name: String) -> Target.Dependency {
    .product(name: name, package: "Traffluent")
}

let hummingbird: Target.Dependency = .product(name: "Hummingbird", package: "hummingbird")
let logging: Target.Dependency = .product(name: "Logging", package: "swift-log")
let system: Target.Dependency = .product(name: "SystemPackage", package: "swift-system")
let httpTypes: Target.Dependency = .product(name: "HTTPTypes", package: "swift-http-types")

func tracing(_ name: String) -> Target.Dependency {
    .product(name: name, package: "swift-distributed-tracing")
}

let targets: [Target] = [
    // The store app, in the order it builds up: its events, the model that tracks them, the
    // analytics that deliver them, and the SwiftUI views.
    .target(name: "StoreEvents", dependencies: [library("EventMacros")], exclude: bazelFiles),
    .target(name: "StoreModel", dependencies: ["StoreEvents", library("Events"), library("Trackers")], exclude: bazelFiles),
    .target(name: "StoreAnalytics", dependencies: [
        "StoreEvents",
        library("AsyncQueues"), library("AutomaticControlTracking"), library("CollectorEncoding"), library("Destinations"),
        library("Events"), library("HTTPDestinations"), library("LifecycleTracking"), library("Persistence"),
        library("Sessions"), library("StandardContext"), library("SwiftUITracking"), library("Trackers"),
        library("TrackingPlans"),
        logging, system,
    ], exclude: bazelFiles),
    .target(name: "StoreViews", dependencies: [
        "StoreAnalytics", "StoreModel",
        library("AutomaticControlTracking"), library("AutomaticScreenTracking"), library("Events"), library("SwiftUITracking"),
        library("Trackers"), library("UIKitTracking"),
    ], exclude: bazelFiles),
    // The executable the export-tracking-plan plugin runs to write the store's tracking plan into
    // TrackingPlan/, and check-tracking-plan runs to check it; its test checks it too.
    .executableTarget(name: "StoreTrackingPlan", dependencies: ["StoreAnalytics", library("TrackingPlans")]),
    // The store's analytics on Linux, without a screen.
    .executableTarget(name: "CommandLineExample", dependencies: [
        "StoreAnalytics", "StoreModel",
        library("HTTPDestinations"), library("LifecycleTracking"), library("Sessions"), library("StandardContext"), library("Trackers"),
        httpTypes, system,
    ]),
    // The server: a stand-in collector for the store app, and routes that track their own requests.
    .target(name: "ExampleServer", dependencies: [library("Events"), library("Trackers"), hummingbird, httpTypes, tracing("Instrumentation"), tracing("Tracing")]),
    .executableTarget(name: "ServerExample", dependencies: ["ExampleServer", library("Destinations"), library("Trackers"), hummingbird, tracing("Tracing")]),

    .testTarget(name: "StoreModelTests", dependencies: ["StoreModel", "StoreEvents", library("Events"), library("Trackers"), library("TrackerTesting")]),
    .testTarget(name: "StoreAnalyticsTests", dependencies: [
        "StoreAnalytics", "StoreEvents", "StoreModel",
        library("CollectorEncoding"), library("Events"), library("HTTPDestinations"), library("Persistence"), library("Trackers"),
        library("AsyncQueues"), library("TrackingPlans"), httpTypes, system,
        .product(name: "Afluent", package: "afluent"),
    ]),
    .testTarget(name: "StoreViewsTests", dependencies: [
        "StoreViews", "StoreAnalytics", "StoreModel", "StoreEvents",
        library("AutomaticControlTracking"), library("Events"), library("SwiftUITracking"), library("Trackers"), library("TrackerTesting"),
        .product(name: "ViewInspector", package: "viewinspector", condition: .when(platforms: [.macOS])),
    ]),
    .testTarget(name: "StoreTrackingPlanTests", dependencies: ["StoreTrackingPlan", library("TrackingPlanTesting")]),
    .testTarget(name: "ExampleServerTests", dependencies: [
        "ExampleServer", "StoreAnalytics", "StoreEvents", "StoreModel",
        library("CollectorEncoding"), library("Destinations"), library("Events"), library("HTTPDestinations"), library("Trackers"),
        library("TrackingPlans"),
        hummingbird, .product(name: "HummingbirdTesting", package: "hummingbird"), system,
        tracing("Instrumentation"), tracing("Tracing"), tracing("InMemoryTracing"),
    ]),
]

let package = Package(
    name: "TraffluentExamples",
    platforms: [.macOS(.v15), .iOS(.v18), .tvOS(.v18), .watchOS(.v11), .visionOS(.v2)],
    dependencies: [
        // Named, so the identity does not depend on the checkout directory's name.
        .package(name: "Traffluent", path: ".."),
        // The analytics tests' gates (SingleValueSubject); the library pins the same version.
        .package(url: "https://github.com/Tyler-Keith-Thompson/Afluent", from: "1.1.49"),
        .package(url: "https://github.com/hummingbird-project/hummingbird", from: "2.29.0"),
        // The server example's tracer, which joins each batch's request to the app's trace.
        .package(url: "https://github.com/apple/swift-distributed-tracing", from: "1.7.4"),
        .package(url: "https://github.com/apple/swift-http-types", from: "1.8.0"),
        // The store's analytics log what they can't save, and keep their records in a FilePath.
        .package(url: "https://github.com/apple/swift-log", from: "1.17.2"),
        .package(url: "https://github.com/apple/swift-system", from: "1.9.0"),
        // 0.x: its minor releases may break its API.
        .package(url: "https://github.com/nalexn/ViewInspector", .upToNextMinor(from: "0.10.5")),
    ],
    targets: targets
)
