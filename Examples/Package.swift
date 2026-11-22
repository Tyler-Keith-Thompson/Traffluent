// swift-tools-version: 6.3
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

let portable: [Target] = [
    .target(name: "ExampleEvents", dependencies: [library("Events")], exclude: bazelFiles),
    .executableTarget(name: "CommandLineExample", dependencies: ["ExampleEvents", library("Destinations"), library("Pipelines")]),
    .testTarget(name: "ExampleEventsTests", dependencies: ["ExampleEvents", library("Destinations"), library("Events"), library("Pipelines")]),
]

let rest: [Target] = [
    .target(name: "ExampleViews", dependencies: ["ExampleEvents", library("Pipelines")], exclude: bazelFiles),
    .target(name: "ExampleServer", dependencies: ["ExampleEvents", library("Pipelines"), hummingbird]),
    .executableTarget(name: "ServerExample", dependencies: ["ExampleServer", "ExampleEvents", library("Destinations"), library("Pipelines"), hummingbird]),
    .testTarget(name: "ExampleViewsTests", dependencies: [
        "ExampleViews", "ExampleEvents", library("Destinations"), library("Events"), library("Pipelines"),
        .product(name: "ViewInspector", package: "viewinspector", condition: .when(platforms: [.macOS])),
    ]),
    .testTarget(name: "ExampleServerTests", dependencies: [
        "ExampleServer", "ExampleEvents", library("Destinations"), library("Events"), library("Pipelines"),
        hummingbird, .product(name: "HummingbirdTesting", package: "hummingbird"),
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
        // 0.x: its minor releases may break its API.
        .package(url: "https://github.com/nalexn/ViewInspector", .upToNextMinor(from: "0.10.5")),
    ]),
    targets: portable + (wasm ? [] : rest)
)
