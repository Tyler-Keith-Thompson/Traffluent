// The Swift examples of the "Exporting and Checking a Tracking Plan" article
// (Sources/Traffluent/Traffluent.docc/TrackingPlanWorkflow.md), verbatim, so the article cannot
// drift from the code, and the signed_up document it shows, byte for byte. Its executable and test
// examples are the example package's StoreTrackingPlan and StoreTrackingPlanTests, quoted
// verbatim, which `just examples-test` builds and runs.

import EventMacros
import Testing
import TrackingPlans

@Suite("Tracking plan examples")
struct TrackingPlanWorkflowExamplesTests {
    @Event(name: "signed_up", consent: .functional)
    struct SignedUp {
        var plan: String
        var email: Sensitive<String>
        var referrer: String?
    }

    @Event(name: "checkout_started", version: 2)
    struct CheckoutStarted {
        var cartSize: Int
        var coupon: String?
    }

    @Test("SignedUp exports as the document the article shows")
    func signedUpDocument() throws {
        let expected = """
            {
              "$id": "signed_up.v1.schema.json",
              "$schema": "https://json-schema.org/draft/2020-12/schema",
              "additionalProperties": false,
              "properties": {
                "email": {
                  "type": "string",
                  "x-traffluent-sensitive": true
                },
                "plan": {
                  "type": "string"
                },
                "referrer": {
                  "type": [
                    "string",
                    "null"
                  ]
                }
              },
              "required": [
                "plan"
              ],
              "title": "signed_up",
              "type": "object",
              "x-traffluent-consent-category": "functional",
              "x-traffluent-version": 1
            }

            """
        let plan = try TrackingPlan(schemas: [SignedUp.schema])

        let document = try #require(plan.files.first { $0.path == "signed_up.v1.schema.json" })
        let actual = String(decoding: document.contents, as: UTF8.self)

        #expect(actual == expected)
    }

    @Test("Exporting a tracking plan")
    func exportingATrackingPlan() throws {
        let plan = try TrackingPlan(schemas: [CheckoutStarted.schema])
        let paths = plan.files.map(\.path)
        // ["tracking-plan.json", "checkout_started.v2.schema.json", "checkout_started.v2.example.json"]

        #expect(paths == ["tracking-plan.json", "checkout_started.v2.schema.json", "checkout_started.v2.example.json"])
    }
}
