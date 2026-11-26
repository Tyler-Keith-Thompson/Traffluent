import Foundation
@testable import StoreTrackingPlan
import Testing
import TrackingPlanTesting

@Suite("StoreTrackingPlan")
struct StoreTrackingPlanTests {
    @Test("The store app's events match its committed tracking plan")
    func eventsMatchTheTrackingPlan() {
        let plan = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("TrackingPlan")
        expectTrackingPlan(StoreTrackingPlan.trackingPlan, matches: plan)
    }
}
