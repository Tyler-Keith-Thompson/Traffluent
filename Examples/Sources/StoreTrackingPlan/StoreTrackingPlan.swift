import StoreEvents
import TrackingPlans

/// Writes the store's tracking plan: `swift package --allow-writing-to-package-directory
/// export-tracking-plan`, from Examples/, writes it into Examples/TrackingPlan.
@main
struct StoreTrackingPlan: TrackingPlanCommand {
    static let trackingPlan = TrackingPlan(schemas: [
        CheckoutStarted.schema,
        OrderCompleted.schema,
        SignedUp.schema,
    ])
}
