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
///     static var trackingPlan: TrackingPlan {
///         get throws(TrackingPlanError) {
///             try TrackingPlan(schemas: [
///                 CheckoutStarted.schema,
///                 SignedUp.schema,
///             ])
///         }
///     }
/// }
/// ```
///
/// Run it with the directory to write the plan's files to (`swift run AppTrackingPlan
/// TrackingPlan`), or let the `export-tracking-plan` command plugin build and run it:
/// `swift package --allow-writing-to-package-directory export-tracking-plan`.
///
/// Run it with `check` and the directory of the committed plan (`swift run AppTrackingPlan check
/// TrackingPlan`), or let the `check-tracking-plan` command plugin do so (`swift package
/// check-tracking-plan`), to fail when the events no longer match that plan, as
/// ``TrackingPlan/check(againstDirectory:)`` compares them.
///
/// It is an executable of the app's own because only code compiled against the app's event types
/// can read their schemas.
public protocol TrackingPlanCommand {
    /// The plan the command writes.
    ///
    /// - Throws: ``TrackingPlanError`` when the events' schemas can't make a plan.
    static var trackingPlan: TrackingPlan { get throws(TrackingPlanError) }
}

extension TrackingPlanCommand {
    /// Writes or checks ``trackingPlan`` as the command's arguments say, and exits.
    ///
    /// Given one argument, a directory, it writes the plan there, as ``TrackingPlan/write(to:)``
    /// does: it exits with status 0 once the plan is written, and 73 (`EX_CANTCREAT`) when a file
    /// can't be written.
    ///
    /// Given `check` and a directory, it compares the plan with the one committed there, as
    /// ``TrackingPlan/check(againstDirectory:)`` does, printing the check's report when they
    /// differ: it exits with status 0 when they match, 1 when a difference is breaking, and 2 when
    /// the committed plan is only out of date.
    ///
    /// Given anything else, `check` alone included (write to `./check` for a directory of that
    /// name), it exits with status 64 (`EX_USAGE`). When ``trackingPlan`` throws, it exits with
    /// status 65 (`EX_DATAERR`). Every failure is printed to standard error.
    public static func main() {
        exit(run(arguments: Array(CommandLine.arguments.dropFirst())))
    }

    /// Writes or checks ``trackingPlan`` as `arguments` say, printing any failure to standard
    /// error, and returns the exit status ``main()`` describes.
    package static func run(arguments: [String]) -> Int32 {
        switch arguments.count {
        case 1 where arguments[0] != "check":
            return withPlan { write($0, to: arguments[0]) }
        case 2 where arguments[0] == "check":
            return withPlan { check($0, against: arguments[1]) }
        default:
            let name = CommandLine.arguments.first.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "tracking-plan"
            printError("usage: \(name) <output-directory>\n       \(name) check <plan-directory>")
            return 64
        }
    }

    /// What `body` returns for ``trackingPlan``, or 65 when it throws.
    private static func withPlan(_ body: (TrackingPlan) -> Int32) -> Int32 {
        let plan: TrackingPlan
        do {
            plan = try trackingPlan
        } catch {
            printError("error: the events' schemas can't make a tracking plan: \(error)")
            return 65
        }
        return body(plan)
    }

    private static func write(_ trackingPlan: TrackingPlan, to directory: String) -> Int32 {
        do {
            try trackingPlan.write(to: URL(fileURLWithPath: directory, isDirectory: true))
            return 0
        } catch {
            printError("error: couldn't write the tracking plan to \(directory): \(error.localizedDescription)")
            return 73
        }
    }

    private static func check(_ trackingPlan: TrackingPlan, against directory: String) -> Int32 {
        let check = trackingPlan.check(againstDirectory: URL(fileURLWithPath: directory, isDirectory: true))
        switch check {
        case .matches:
            return 0
        case .breaking:
            printError("error: \(directory): \(check)")
            return 1
        case .outOfDate:
            printError("error: \(directory): \(check)")
            return 2
        }
    }
}

private func printError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}
