// The example of the Sessions module's landing article
// (Sources/Sessions/Sessions.docc/Sessions.md), verbatim, so the article cannot drift from the code.

import Testing
import Traffluent

@Suite("Sessions module examples", .timeLimit(.minutes(1)))
struct SessionsModuleExamplesTests {
    struct SignedUp: Event {
        var plan: String
    }

    @Test("Sessions: a timeout and one kind of session event")
    func sessions() async {
        let tracker = Tracker(enrichers: [.sessions(timeout: .seconds(15 * 60), kinds: [.started])])
        tracker.track(SignedUp(plan: "pro"))  // tracks SessionStarted, then SignedUp, both with the same SessionKey
        await tracker.finish()

        var actual: [EventRecord] = []
        for await record in tracker.records {
            actual.append(record)
        }
        let expectedNames = ["SessionStarted", "SignedUp"]
        let keys = actual.compactMap { $0.context[SessionKey.self] }
        #expect(actual.map(\.name) == expectedNames)
        #expect(keys.count == 2)
        #expect(Set(keys).count == 1)
    }
}
