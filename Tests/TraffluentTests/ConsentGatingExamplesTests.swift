// The example of the "Consent Gating" article
// (Sources/Traffluent/Traffluent.docc/ConsentGating.md), verbatim, so the article cannot drift from
// the code.

import Testing
import Traffluent

// Private: its events share their names with other events of this test target, and @Event
// leaves a private type's events out of the link check of names (DefiningEvents, Limits).
@Suite("Consent gating examples", .timeLimit(.minutes(1)))
private struct ConsentGatingExamplesTests {
    @Event
    struct SignedUp {
        var plan: String
    }

    @Event(consent: .advertising)
    struct AdClicked {
        var campaign: String
    }

    @Test("Consent")
    func consent() async throws {
        let consent = Consent([.analytics: .granted])
        let tracker = Tracker(consent: consent)
        let delivery = tracker.records.batch().deliver(
            to: ConsoleDestination(),
            ConsoleDestination().accepting(.advertising)
        )
        tracker.track(SignedUp(plan: "pro"))          // delivered: analytics is granted
        tracker.track(AdClicked(campaign: "spring"))  // held: advertising is undecided
        consent.grant(.advertising)                   // delivers the held AdClicked
        await tracker.finish()
        try await delivery.execute()

        #expect(consent.heldRecordCount == 0)
    }
}
