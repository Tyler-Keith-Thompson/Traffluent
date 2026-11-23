import Foundation

/// An executable that writes a tracking plan: the type marked `@main` in a target of the app's
/// package that lists its events.
///
/// ```swift
/// import AppEvents
/// import TrackingPlans
///
/// @main
/// struct AppTrackingPlan: TrackingPlanCommand {
///     static let trackingPlan = TrackingPlan(schemas: [
///         CheckoutStarted.schema,
///         SignedUp.schema,
///     ])
/// }
/// ```
///
/// Run it with the directory to write the plan's files to (`swift run AppTrackingPlan
/// TrackingPlan`), or let the `export-tracking-plan` command plugin build and run it:
/// `swift package --allow-writing-to-package-directory export-tracking-plan`.
///
/// It is an executable of the app's own because only code compiled against the app's event types
/// can read their schemas.
public protocol TrackingPlanCommand {
    /// The plan the command writes.
    static var trackingPlan: TrackingPlan { get }
}

extension TrackingPlanCommand {
    /// Writes ``trackingPlan`` into the directory named by the command's one argument, as
    /// ``TrackingPlan/write(to:)`` does, and exits.
    ///
    /// It exits with status 0 once the plan is written, 64 (`EX_USAGE`) when it isn't given exactly
    /// one argument, and 73 (`EX_CANTCREAT`) when a file can't be written, printing why to
    /// standard error.
    public static func main() {
        exit(run(arguments: Array(CommandLine.arguments.dropFirst())))
    }

    /// Writes ``trackingPlan`` into the directory `arguments` name, printing any failure to
    /// standard error, and returns the exit status ``main()`` describes.
    package static func run(arguments: [String]) -> Int32 {
        guard arguments.count == 1, let directory = arguments.first else {
            printError("usage: \(CommandLine.arguments.first.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "tracking-plan") <output-directory>")
            return 64
        }
        do {
            try trackingPlan.write(to: URL(fileURLWithPath: directory, isDirectory: true))
            return 0
        } catch {
            printError("error: couldn't write the tracking plan to \(directory): \(error.localizedDescription)")
            return 73
        }
    }
}

private func printError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}
