// The test helper, checked from Swift Testing itself: a known issue whose comment is the check's
// report when the plan differs, and no issue when it matches.

import Events
import Foundation
import Testing
import TrackingPlanTesting
import TrackingPlans

@Suite("expectTrackingPlan")
struct ExpectTrackingPlanTests {
    static let plan = TrackingPlan(schemas: [
        EventSchema(name: "checkout_started", version: 2, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "cartSize", typeName: "Int", isOptional: false),
        ]),
    ])

    @Test("A plan that matches the committed one records no issue and returns the match")
    func matches() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try ExpectTrackingPlanTests.plan.write(to: directory)
        let expected = TrackingPlanCheck.matches

        let actual = expectTrackingPlan(ExpectTrackingPlanTests.plan, matches: directory)

        #expect(actual == expected)
    }

    @Test("A plan that breaks the committed one records an issue whose comment is the directory and the check's report, and returns the check")
    func breaking() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let committed = TrackingPlan(schemas: [
            EventSchema(name: "checkout_started", version: 2, consentCategory: .analytics, properties: [
                EventSchema.Property(name: "cartSize", typeName: "Int", isOptional: true),
            ]),
        ])
        try committed.write(to: directory)
        let expectedCheck = TrackingPlanCheck.breaking([.propertyMadeRequired(event: "checkout_started", version: 2, property: "cartSize")])
        let expected = directory.path + ": " + expectedCheck.description
        var actual: TrackingPlanCheck?

        withKnownIssue {
            actual = expectTrackingPlan(ExpectTrackingPlanTests.plan, matches: directory)
        } matching: { issue in
            issue.comments.map(\.rawValue) == [expected]
        }

        #expect(actual == expectedCheck)
    }

    @Test("A committed plan that is only out of date records an issue too")
    func outOfDate() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try TrackingPlan(schemas: []).write(to: directory)
        let expected = directory.path + ": " + ExpectTrackingPlanTests.plan.check(againstDirectory: directory).description

        withKnownIssue {
            expectTrackingPlan(ExpectTrackingPlanTests.plan, matches: directory)
        } matching: { issue in
            issue.comments.map(\.rawValue) == [expected]
        }
    }

    @Test("The issue is recorded at the call's source location")
    func sourceLocation() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let expected = #_sourceLocation

        withKnownIssue {
            expectTrackingPlan(ExpectTrackingPlanTests.plan, matches: directory, sourceLocation: expected)
        } matching: { issue in
            issue.sourceLocation == expected
        }
    }
}
