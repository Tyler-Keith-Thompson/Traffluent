import StoreAnalytics
import TrackingPlans

/// Writes the store app's tracking plan, `TrackingPlan.store`: `swift package
/// --allow-writing-to-package-directory export-tracking-plan`, from Examples/, writes it into
/// Examples/TrackingPlan, and `swift package check-tracking-plan` checks the events against it.
@main
struct StoreTrackingPlan: TrackingPlanCommand {
    static let trackingPlan = TrackingPlan.store
}
