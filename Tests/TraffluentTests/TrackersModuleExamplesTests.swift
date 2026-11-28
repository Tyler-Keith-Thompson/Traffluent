// The example of the Trackers module's landing article
// (Sources/Trackers/Trackers.docc/Trackers.md), verbatim, so the article cannot drift from the code.

import Instrumentation
import Testing
import Traffluent

// Private: its events share their names with other events of this test target, and @Event
// leaves a private type's events out of the link check of names (DefiningEvents, Limits).
@Suite("Trackers module examples", .timeLimit(.minutes(1)))
private struct TrackersModuleExamplesTests {
    @Event
    struct SignedUp {
        var plan: String
    }

    enum ExperimentKey: ServiceContextKey {
        typealias Value = String
    }

    @Test("A tracker with a consent and an enricher, bound to a task")
    func trackerWithConsentAndEnricher() async {
        var actual: [String] = []

        let consent = Consent([.analytics: .granted])
        let tracker = Tracker(
            consent: consent,
            enrichers: [Enricher { $0[ExperimentKey.self] = "new-checkout" }]
        )
        withTracker(tracker) {
            Tracker.current.track(SignedUp(plan: "pro"))
        }
        await tracker.finish()
        for await record in tracker.records {
            print(record.name, record.context[ExperimentKey.self] ?? "none")  // SignedUp new-checkout
            actual.append("\(record.name) \(record.context[ExperimentKey.self] ?? "none")")
        }

        let expected = ["SignedUp new-checkout"]
        #expect(actual == expected)
    }
}
