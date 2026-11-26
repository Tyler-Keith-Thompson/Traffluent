public import Foundation
public import Testing
public import TrackingPlans

/// Records a Swift Testing issue when `plan` no longer matches the plan committed in
/// `directory`, its comment the check's report, as the `check` command prints it.
///
/// Call it from a test of the app's, so the check runs wherever its tests do:
///
/// ```swift
/// import Foundation
/// import Testing
/// import TrackingPlanTesting
/// @testable import AppTrackingPlan
///
/// @Test func eventsMatchTheTrackingPlan() throws {
///     let plan = URL(fileURLWithPath: #filePath)
///         .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
///         .appendingPathComponent("TrackingPlan")
///     expectTrackingPlan(try AppTrackingPlan.trackingPlan, matches: plan)
/// }
/// ```
///
/// An out-of-date plan fails the test as a breaking one does: either way, the committed plan
/// isn't what exporting the events writes.
///
/// - Parameters:
///   - plan: The plan the app's events make now.
///   - directory: The directory the committed plan was exported to.
///   - sourceLocation: Where the issue is recorded; the call's location by default.
/// - Returns: The check, ``/TrackingPlans/TrackingPlanCheck/matches`` when no issue was recorded.
@discardableResult
public func expectTrackingPlan(
    _ plan: TrackingPlan,
    matches directory: URL,
    sourceLocation: SourceLocation = #_sourceLocation
) -> TrackingPlanCheck {
    let check = plan.check(againstDirectory: directory)
    if check != .matches {
        Issue.record(Comment(rawValue: "\(directory.path): \(check)"), sourceLocation: sourceLocation)
    }
    return check
}
