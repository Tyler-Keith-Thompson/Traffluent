// The example of the TrackingPlanTesting module's landing article
// (Sources/TrackingPlanTesting/TrackingPlanTesting.docc/TrackingPlanTesting.md), verbatim, so the
// article cannot drift from the code. The example is itself a test of an app whose plan is
// committed beside it; this target commits none, so its body runs here twice: once as it stands,
// where the missing plan is the issue it records, and once against a plan exported first.

import EventMacros
import Foundation
import Testing
import TrackingPlans
import TrackingPlanTesting

@Suite("TrackingPlanTesting module examples")
struct TrackingPlanTestingModuleExamplesTests {
    @Event(name: "signed_up")
    struct SignedUp {
        var plan: String
    }

    enum AppTrackingPlan {
        static let trackingPlan = TrackingPlan(schemas: [SignedUp.schema])
    }

    // The example's test, verbatim but for its @Test attribute, which the test below stands in for.
    func eventsMatchTheTrackingPlan() {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("TrackingPlan")
        expectTrackingPlan(AppTrackingPlan.trackingPlan, matches: directory)
    }

    @Test("With no plan committed beside the test, it records an issue")
    func missingPlanRecordsAnIssue() {
        withKnownIssue {
            eventsMatchTheTrackingPlan()
        }
    }

    @Test("Against the plan its events export, it records none")
    func eventsMatchAnExportedTrackingPlan() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TrackingPlanTestingModuleExamplesTests-\(UUID().uuidString)")
            .appendingPathComponent("TrackingPlan")
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
        try AppTrackingPlan.trackingPlan.write(to: directory)

        let actual = expectTrackingPlan(AppTrackingPlan.trackingPlan, matches: directory)

        #expect(actual == .matches)
    }
}
