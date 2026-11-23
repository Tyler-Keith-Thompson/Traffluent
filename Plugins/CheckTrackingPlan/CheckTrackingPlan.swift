import Foundation
import PackagePlugin

/// `swift package check-tracking-plan [--product <name>] [--plan <directory>]`: builds the
/// package's `TrackingPlanCommand` executable and runs it as `check <directory>`, so it fails, with
/// a line naming each event and property that changed, when the events no longer match the plan
/// committed in `<directory>`, `TrackingPlan` in the package by default.
///
/// A plugin of its own rather than a flag of `export-tracking-plan`, because checking only reads:
/// it needs no `--allow-writing-to-package-directory`, which keeps the command CI runs plain.
@main
struct CheckTrackingPlan: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) async throws {
        var extractor = ArgumentExtractor(arguments)
        let products = extractor.extractOption(named: "product")
        let plans = extractor.extractOption(named: "plan")
        guard extractor.remainingArguments.isEmpty, products.count <= 1, plans.count <= 1 else {
            throw CheckError("usage: swift package check-tracking-plan [--product <name>] [--plan <directory>]")
        }
        let product = try context.package.trackingPlanCommand(named: products.first)
        let plan = URL(fileURLWithPath: plans.first ?? "TrackingPlan", relativeTo: context.package.directoryURL).standardizedFileURL

        let build = try packageManager.build(.product(product), parameters: .init(configuration: .debug, logging: .concise))
        guard build.succeeded else {
            throw CheckError("\(build.logText)\ncouldn't build \(product)")
        }
        guard let executable = build.builtArtifacts.first(where: { $0.kind == .executable }) else {
            throw CheckError("\(product) is not an executable")
        }

        // The command prints the check's report to standard error, which the process shares.
        let process = Process()
        process.executableURL = executable.url
        process.arguments = ["check", plan.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            throw CheckError("the events don't match the tracking plan in \(plan.path)")
        }
        print("The events match the tracking plan in \(plan.path)")
    }
}

// The same lookup as ExportTrackingPlan's, copied: a command plugin can depend on no library, so
// two plugins can't share the code.
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
                throw CheckError("\(name) is not an executable target of the package that depends on TrackingPlans")
            }
            return name
        }
        guard commands.count == 1, let command = commands.first else {
            let found = commands.isEmpty ? "none" : commands.joined(separator: ", ")
            throw CheckError(
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
struct CheckError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
