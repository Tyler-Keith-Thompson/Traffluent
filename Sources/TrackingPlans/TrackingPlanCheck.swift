/// What checking a tracking plan against the committed one found: a match, a committed plan that
/// is only out of date, or differences that break it.
///
/// Its ``description`` is the report the `check` command prints and the test helper records.
public enum TrackingPlanCheck: Sendable, Hashable, CustomStringConvertible {
    /// The committed plan is the one exporting the events writes now, byte for byte.
    case matches
    /// The committed plan differs only in ways that leave its payloads valid; export it again.
    case outOfDate([TrackingPlanDifference])
    /// At least one difference is breaking; the array holds every difference, breaking or not.
    case breaking([TrackingPlanDifference])

    /// The check of `differences`: breaking when one is, out of date when there are any, and
    /// matching otherwise.
    init(differences: [TrackingPlanDifference]) {
        if differences.contains(where: \.isBreaking) {
            self = .breaking(differences)
        } else if differences.isEmpty {
            self = .matches
        } else {
            self = .outOfDate(differences)
        }
    }

    /// Every difference found, in the order the committed plan lists its events, then the new
    /// events'; empty when the plans match.
    public var differences: [TrackingPlanDifference] {
        switch self {
        case .matches: []
        case .outOfDate(let differences), .breaking(let differences): differences
        }
    }

    /// The report: a line saying what was found, then each difference on a line of its own, the
    /// breaking ones first, and what to do about them.
    public var description: String {
        switch self {
        case .matches:
            return "The events match the committed tracking plan."
        case .outOfDate(let differences):
            return (["The committed tracking plan is out of date:"] + differences.map { "  - \($0)" } + [TrackingPlanCheck.exportAdvice])
                .joined(separator: "\n")
        case .breaking(let differences):
            let breaking = differences.filter(\.isBreaking)
            let others = differences.filter { !$0.isBreaking }
            var lines = ["The events break the committed tracking plan: at the same version, a stored record or an already-released app's payload may no longer decode or validate."]
            lines += breaking.map { "  - \($0)" }
            if !others.isEmpty {
                lines.append("It is also out of date:")
                lines += others.map { "  - \($0)" }
            }
            lines.append("Undo each breaking change, or raise the version of each event that changed (@Event(version:)), then export the plan again: " + TrackingPlanCheck.exportCommand)
            return lines.joined(separator: "\n")
        }
    }

    private static let exportCommand = "swift package --allow-writing-to-package-directory export-tracking-plan"

    private static let exportAdvice = "Export it again: " + exportCommand
}
