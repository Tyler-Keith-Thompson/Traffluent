import Foundation
import HTTPDestinations
import MixpanelEncoding
import Testing
import TrackingPlans

@Suite("HTTPDestination.mixpanel: setup errors")
struct MixpanelSetupErrorTests {
    @Test("The factory throws emptyProjectToken for a token that is empty or only whitespace", arguments: ["", " ", " \n\t"])
    func emptyProjectToken(token: String) throws {
        let plan = try TrackingPlan(schemas: [])

        #expect(throws: MixpanelSetupError.emptyProjectToken) {
            try HTTPDestination.mixpanel(projectToken: token, region: .us, plan: plan)
        }
    }

    @Test("The factory accepts a one-character token, the shortest that isn't empty, in every region", arguments: [MixpanelRegion.us, .eu, .india])
    func shortestToken(region: MixpanelRegion) throws {
        let plan = try TrackingPlan(schemas: [])

        #expect(throws: Never.self) {
            try HTTPDestination.mixpanel(projectToken: "a", region: region, plan: plan)
        }
    }

    // Mixpanel's tokens are alphanumeric (https://docs.mixpanel.com/reference/project-token).
    @Test("The factory throws malformedProjectToken for a token with any character but an ASCII letter or digit, and accepts every letter and digit", arguments: [
        ("0123456789abcdef0123456789abcdef", false), ("azAZ09", false), ("Z", false), ("0", false), (" 9z\n", false),
        ("name.1a2b3c.mp-service-account", true), ("abc def", true), ("abc-def", true), ("abc_def", true), ("abc/", true), ("abc:", true),
        ("abc@", true), ("abc[", true), ("abc`", true), ("abc{", true), ("abcé", true), ("abc٣", true), ("Basic YWJjOg==", true),
    ])
    func malformedProjectToken(token: String, throwsError: Bool) throws {
        let plan = try TrackingPlan(schemas: [])
        let expected: MixpanelSetupError? = throwsError ? .malformedProjectToken : nil

        let actual: MixpanelSetupError?
        do {
            _ = try HTTPDestination.mixpanel(projectToken: token, region: .us, plan: plan)
            actual = nil
        } catch {
            actual = error
        }

        #expect(actual == expected)
    }
}
