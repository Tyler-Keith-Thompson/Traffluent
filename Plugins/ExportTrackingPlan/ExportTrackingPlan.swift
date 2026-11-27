import Foundation
import PackagePlugin

/// `swift package --allow-writing-to-package-directory export-tracking-plan [--product <name>]
/// [--output <directory>] [--iglu-vendor <vendor> --iglu-registry server|static
/// [--iglu-output <directory>]]`: builds the package's `TrackingPlanCommand` executable and runs
/// it, so it writes the tracking plan's files into `<directory>`, `TrackingPlan` in the package by
/// default. With `--iglu-vendor`, it runs it again to write the plan's events as the schemas of an
/// Iglu registry under that vendor into the `--iglu-output` directory, `Iglu` in the package by
/// default: for Iglu Server (`server`) or a static repository (`static`), which `--iglu-registry`
/// names, as only Iglu Server publishes a change at an event's version.
///
/// The plugin can't read an app's event types itself: only code compiled against them can. So it
/// builds the executable the package declares for the purpose and runs that: an executable target
/// that depends on TrackingPlans, the one named by `--product` or else the package's only one.
@main
struct ExportTrackingPlan: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) async throws {
        var extractor = ArgumentExtractor(arguments)
        let products = extractor.extractOption(named: "product")
        let outputs = extractor.extractOption(named: "output")
        let igluVendors = extractor.extractOption(named: "iglu-vendor")
        let igluOutputs = extractor.extractOption(named: "iglu-output")
        let igluRegistries = extractor.extractOption(named: "iglu-registry")
        // An Iglu directory or kind without a vendor would write nothing, so it is refused as a
        // slip; the kind has no default, as the wrong one publishes schemas events then fail.
        guard extractor.remainingArguments.isEmpty, products.count <= 1, outputs.count <= 1, igluVendors.count <= 1, igluOutputs.count <= igluVendors.count,
            igluRegistries.count == igluVendors.count, igluRegistries.allSatisfy({ ["server", "static"].contains($0) })
        else {
            throw ExportError(
                "usage: swift package --allow-writing-to-package-directory export-tracking-plan [--product <name>] [--output <directory>] [--iglu-vendor <vendor> --iglu-registry server|static [--iglu-output <directory>]]"
            )
        }
        let product = try context.package.trackingPlanCommand(named: products.first)
        let output = URL(fileURLWithPath: outputs.first ?? "TrackingPlan", relativeTo: context.package.directoryURL).standardizedFileURL

        let build = try packageManager.build(.product(product), parameters: .init(configuration: .debug, logging: .concise))
        guard build.succeeded else {
            throw ExportError("\(build.logText)\ncouldn't build \(product)")
        }
        guard let executable = build.builtArtifacts.first(where: { $0.kind == .executable }) else {
            throw ExportError("\(product) is not an executable")
        }

        try run(executable.url, arguments: [output.path], product: product)
        print("Wrote the tracking plan to \(output.path)")

        if let vendor = igluVendors.first, let registry = igluRegistries.first {
            let igluOutput = URL(fileURLWithPath: igluOutputs.first ?? "Iglu", relativeTo: context.package.directoryURL).standardizedFileURL
            try run(executable.url, arguments: ["iglu", vendor, registry, igluOutput.path], product: product)
            print("Wrote the Iglu registry to \(igluOutput.path)")
        }
    }

    /// Runs the plan's executable with `arguments`, throwing unless it exits with status 0.
    private func run(_ executable: URL, arguments: [String], product: String) throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            throw ExportError("\(product) exited with status \(process.terminationStatus)")
        }
    }
}

extension Package {
    /// The name of the package's executable target that depends on TrackingPlans, which is also
    /// the name of its executable product: the one named `name`, or else the package's only one.
    fileprivate func trackingPlanCommand(named name: String?) throws -> String {
        let commands = targets
            .compactMap { $0 as? SourceModuleTarget }
            .filter { $0.kind == .executable && $0.dependsOnTrackingPlans }
            .map(\.name)
            .sorted()
        if let name {
            guard commands.contains(name) else {
                throw ExportError("\(name) is not an executable target of the package that depends on TrackingPlans")
            }
            return name
        }
        guard commands.count == 1, let command = commands.first else {
            let found = commands.isEmpty ? "none" : commands.joined(separator: ", ")
            throw ExportError(
                "the package needs one executable target that depends on TrackingPlans and declares a TrackingPlanCommand (found: \(found)); name one with --product"
            )
        }
        return command
    }
}

extension SourceModuleTarget {
    fileprivate var dependsOnTrackingPlans: Bool {
        dependencies.contains { dependency in
            switch dependency {
            case .product(let product): product.name == "TrackingPlans"
            case .target(let target): target.name == "TrackingPlans"
            @unknown default: false
            }
        }
    }
}

/// A failure the plugin reports with its message alone, which SwiftPM prefixes with `error:`.
struct ExportError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
