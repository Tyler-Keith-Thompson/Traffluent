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
/// ``TrackingPlan/check(againstDirectory:)`` compares them. With `--breaking-only`
/// (`swift package check-tracking-plan --plan <directory> --breaking-only`) it fails only when a
/// difference is breaking, so CI can check the events against the base branch's plan.
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
    /// Given `check --breaking-only` and a directory, it compares them the same way but fails only
    /// when a difference is breaking: it exits with status 1 then, printing the report, and 0 when
    /// they match or the plan there is only out of date. It prints the differences of an
    /// out-of-date plan to standard output, as information.
    ///
    /// Given anything else, it exits with status 64 (`EX_USAGE`): `check` alone (write to `./check`
    /// for a directory of that name), `check --breaking-only` alone, the flag in any other place,
    /// or a directory whose name starts with `-`, as a mistyped option would (write `./-name` for
    /// one). When ``trackingPlan`` throws, it exits with status 65 (`EX_DATAERR`). Every failure is
    /// printed to standard error.
    public static func main() {
        let result = run(arguments: Array(CommandLine.arguments.dropFirst()))
        write(result.standardOutput, to: .standardOutput)
        write(result.standardError, to: .standardError)
        exit(result.status)
    }

    /// Writes or checks ``trackingPlan`` as `arguments` say, and returns the status ``main()``
    /// describes and what to print.
    package static func run(arguments: [String]) -> TrackingPlanCommandResult {
        switch arguments.count {
        case 1 where arguments[0] != "check" && !arguments[0].isOption:
            return withPlan { write($0, to: arguments[0]) }
        case 2 where arguments[0] == "check" && !arguments[1].isOption:
            return withPlan { check($0, against: arguments[1]) }
        case 3 where arguments[0] == "check" && arguments[1] == breakingOnlyFlag && !arguments[2].isOption:
            return withPlan { checkBreakingOnly($0, against: arguments[2]) }
        default:
            let name = CommandLine.arguments.first.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "tracking-plan"
            let usage = "usage: \(name) <output-directory>\n       \(name) check [\(breakingOnlyFlag)] <plan-directory>"
            return TrackingPlanCommandResult(status: 64, standardError: usage)
        }
    }

    // check-tracking-plan passes its own flag of this name through.
    private static var breakingOnlyFlag: String { "--breaking-only" }

    /// What `body` returns for ``trackingPlan``, or 65 when it throws.
    private static func withPlan(_ body: (TrackingPlan) -> TrackingPlanCommandResult) -> TrackingPlanCommandResult {
        let plan: TrackingPlan
        do {
            plan = try trackingPlan
        } catch {
            return TrackingPlanCommandResult(status: 65, standardError: "error: the events' schemas can't make a tracking plan: \(error)")
        }
        return body(plan)
    }

    private static func write(_ trackingPlan: TrackingPlan, to directory: String) -> TrackingPlanCommandResult {
        do {
            try trackingPlan.write(to: URL(fileURLWithPath: directory, isDirectory: true))
            return TrackingPlanCommandResult(status: 0)
        } catch {
            let message = "error: couldn't write the tracking plan to \(directory): \(error.localizedDescription)"
            return TrackingPlanCommandResult(status: 73, standardError: message)
        }
    }

    private static func check(_ trackingPlan: TrackingPlan, against directory: String) -> TrackingPlanCommandResult {
        let check = trackingPlan.check(againstDirectory: URL(fileURLWithPath: directory, isDirectory: true))
        switch check {
        case .matches:
            return TrackingPlanCommandResult(status: 0)
        case .breaking:
            return TrackingPlanCommandResult(status: 1, standardError: "error: \(directory): \(check)")
        case .outOfDate:
            return TrackingPlanCommandResult(status: 2, standardError: "error: \(directory): \(check)")
        }
    }

    // The out-of-date report's advice to export the plan again is left out: the plan checked this
    // way is usually the base branch's, which exporting the change's events doesn't write.
    private static func checkBreakingOnly(_ trackingPlan: TrackingPlan, against directory: String) -> TrackingPlanCommandResult {
        let check = trackingPlan.check(againstDirectory: URL(fileURLWithPath: directory, isDirectory: true))
        switch check {
        case .matches:
            return TrackingPlanCommandResult(status: 0)
        case .breaking:
            return TrackingPlanCommandResult(status: 1, standardError: "error: \(directory): \(check)")
        case .outOfDate(let differences):
            let lines = ["note: \(directory): the events differ from this tracking plan, but no difference is breaking:"] + differences.map { "  - \($0)" }
            return TrackingPlanCommandResult(status: 0, standardOutput: lines.joined(separator: "\n"))
        }
    }

    /// Writes `message` and a newline to `stream`, or nothing when `message` is empty.
    private static func write(_ message: String, to stream: FileHandle) {
        guard !message.isEmpty else { return }
        stream.write(Data((message + "\n").utf8))
    }
}

extension String {
    /// Whether the argument is spelled as an option, which the command never takes for a directory.
    fileprivate var isOption: Bool {
        hasPrefix("-")
    }
}
