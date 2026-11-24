// The first example of the "Exporting and Checking a Tracking Plan" article
// (Sources/Traffluent/Traffluent.docc/TrackingPlanWorkflow.md), verbatim, so the article cannot
// drift from the code. Its executable and test examples are the example package's
// StoreTrackingPlan and StoreTrackingPlanTests, quoted verbatim, which `just examples-test` builds
// and runs.

import EventMacros
import Testing
import TrackingPlans

@Suite("Tracking plan examples")
struct TrackingPlanWorkflowExamplesTests {
    @Event(name: "checkout_started", version: 2)
    struct CheckoutStarted {
        var cartSize: Int
        var coupon: String?
    }

    @Test("Exporting a tracking plan")
    func exportingATrackingPlan() {
        let plan = TrackingPlan(schemas: [CheckoutStarted.schema])
        let paths = plan.files.map(\.path)
        // ["tracking-plan.json", "checkout_started.v2.schema.json", "checkout_started.v2.example.json"]

        #expect(paths == ["tracking-plan.json", "checkout_started.v2.schema.json", "checkout_started.v2.example.json"])
    }
}
