// The example of the TrackingPlans module's landing article
// (Sources/TrackingPlans/TrackingPlans.docc/TrackingPlans.md), verbatim, so the article cannot
// drift from the code.

import Testing
import TrackingPlans
import Traffluent

@Suite("TrackingPlans module examples")
struct TrackingPlansModuleExamplesTests {
    @Event(name: "signed_up")
    struct SignedUp {
        var plan: String
    }

    @Test("A plan's files, checked against themselves")
    func trackingPlans() {
        let plan = TrackingPlan(schemas: [SignedUp.schema])
        let check = plan.check(against: plan.files)  // .matches
        let paths = plan.files.map(\.path)
        // ["tracking-plan.json", "signed_up.v1.schema.json", "signed_up.v1.example.json"]

        let expectedPaths = ["tracking-plan.json", "signed_up.v1.schema.json", "signed_up.v1.example.json"]
        #expect(check == .matches)
        #expect(paths == expectedPaths)
    }
}
