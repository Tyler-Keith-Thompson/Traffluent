import AmplitudeEncoding
import Foundation
import HTTPDestinations
import Testing
import TrackingPlans

@Suite("HTTPDestination.amplitude: setup errors")
struct AmplitudeSetupErrorTests {
    @Test("The factory throws emptyAPIKey for a key that is empty or only whitespace", arguments: ["", " ", " \n\t"])
    func emptyAPIKey(key: String) throws {
        let plan = try TrackingPlan(schemas: [])

        #expect(throws: AmplitudeSetupError.emptyAPIKey) {
            try HTTPDestination.amplitude(apiKey: key, region: .us, plan: plan)
        }
    }

    @Test("The factory accepts a one-character key, the shortest that isn't empty, in either region", arguments: [AmplitudeRegion.us, .eu])
    func shortestKey(region: AmplitudeRegion) throws {
        let plan = try TrackingPlan(schemas: [])

        #expect(throws: Never.self) {
            try HTTPDestination.amplitude(apiKey: "a", region: region, plan: plan)
        }
    }

    @Test("The factory throws deploymentKey for an Experiment deployment key, whitespace around it trimmed, and accepts API keys and keys that only resemble one", arguments: [
        ("client-", true), ("client-abc", true), ("server-abc", true), (" server-abc", true), ("\nclient-abc\t", true),
        ("0123456789abcdef0123456789abcdef", false), ("client", false), ("server", false), ("Client-abc", false), ("SERVER-abc", false), ("x client-abc", false), ("clientabc", false),
    ])
    func deploymentKey(key: String, throwsError: Bool) throws {
        let plan = try TrackingPlan(schemas: [])
        let expected: AmplitudeSetupError? = throwsError ? .deploymentKey : nil

        let actual: AmplitudeSetupError?
        do {
            _ = try HTTPDestination.amplitude(apiKey: key, region: .us, plan: plan)
            actual = nil
        } catch {
            actual = error
        }

        #expect(actual == expected)
    }
}
