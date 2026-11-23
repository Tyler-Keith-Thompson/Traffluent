import Foundation
import PackagePlugin

/// `swift package --allow-writing-to-package-directory export-tracking-plan [--product <name>]
/// [--output <directory>]`: builds the package's `TrackingPlanCommand` executable and runs it, so it
/// writes the tracking plan's files into `<directory>`, `TrackingPlan` in the package by default.
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
        guard extractor.remainingArguments.isEmpty, products.count <= 1, outputs.count <= 1 else {
            throw ExportError(
                "usage: swift package --allow-writing-to-package-directory export-tracking-plan [--product <name>] [--output <directory>]"
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

        let process = Process()
        process.executableURL = executable.url
        process.arguments = [output.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            throw ExportError("\(product) exited with status \(process.terminationStatus)")
        }
        print("Wrote the tracking plan to \(output.path)")
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
