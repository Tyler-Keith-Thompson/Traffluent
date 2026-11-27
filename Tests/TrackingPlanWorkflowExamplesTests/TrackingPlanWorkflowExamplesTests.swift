// The Swift examples of the "Exporting and Checking a Tracking Plan" article
// (Sources/Traffluent/Traffluent.docc/TrackingPlanWorkflow.md), verbatim, so the article cannot
// drift from the code, and the signed_up document it shows, byte for byte. Its executable and test
// examples are the example package's StoreTrackingPlan and StoreTrackingPlanTests, quoted
// verbatim, which `just examples-test` builds and runs.

import EventMacros
import Foundation
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
        let plan = try TrackingPlan()
        let paths = plan.files.map(\.path)
        // ["tracking-plan.json", ..., "checkout_started.v2.schema.json", "checkout_started.v2.example.json", ...]
        let expectedPaths = ["tracking-plan.json", "checkout_started.v2.schema.json", "checkout_started.v2.example.json"]

        #expect(paths.first == expectedPaths.first)
        #expect(expectedPaths.allSatisfy(paths.contains))
    }

    @Test("SignedUp exports to an Iglu registry as the file the article shows")
    func signedUpIgluFile() throws {
        let expected = """
            {
              "$schema": "http://iglucentral.com/schemas/com.snowplowanalytics.self-desc/schema/jsonschema/1-0-0#",
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
              "self": {
                "format": "jsonschema",
                "name": "signed_up",
                "vendor": "com.example",
                "version": "1-0-0"
              },
              "title": "signed_up",
              "type": "object",
              "x-traffluent-consent-category": "functional",
              "x-traffluent-version": 1
            }

            """
        let plan = try TrackingPlan(schemas: [SignedUp.schema])

        let file = try #require(try plan.igluFiles(vendor: "com.example", registry: .server, carryingForward: []).first)
        let actual = String(decoding: file.contents, as: UTF8.self)

        #expect(actual == expected)
    }

    @Test("Exporting an Iglu registry")
    func exportingAnIgluRegistry() throws {
        let registry = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: registry) }

        let plan = try TrackingPlan(schemas: [SignedUp.schema])
        try plan.writeIgluRegistry(to: registry, vendor: "com.example", registry: .server)
        // registry/schemas/com.example/signed_up/jsonschema/1-0-0

        let expected = try #require(try plan.igluFiles(vendor: "com.example", registry: .server, carryingForward: []).first).contents
        let actual = FileManager.default.contents(atPath: registry.appendingPathComponent("schemas/com.example/signed_up/jsonschema/1-0-0").path)
        #expect(actual == Data(expected))
    }
}
