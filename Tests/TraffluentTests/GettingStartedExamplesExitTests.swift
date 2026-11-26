// The "Getting Started" article's (Sources/Traffluent/Traffluent.docc/GettingStarted.md) example
// of `Tracker.bootstrap`, verbatim. An exit test, in a file of its own: its body runs in a child
// process, which iOS, tvOS, watchOS and visionOS cannot start. A child process because the
// bootstrapped tracker is the process's default for good, and nothing can reset it, so
// bootstrapping in the test process would change `Tracker.current` for every other test running
// beside it. No test in the test process calls `Tracker.bootstrap`.

import Foundation
import Testing
import Traffluent

@Suite("Getting started examples: bootstrap", .timeLimit(.minutes(1)))
struct GettingStartedExamplesExitTests {
    @Event(name: "signed_up")
    struct SignedUp {
        var plan: String
    }

    @Test("A bootstrapped tracker is Tracker.current where no binding reaches, and a second bootstrap throws TrackerAlreadyBootstrapped")
    func bootstrap() async {
        await #expect(processExitsWith: .success) {
            let tracker = Tracker()
            let expected = ["plus"]
            let expectedError: TrackerAlreadyBootstrapped? = TrackerAlreadyBootstrapped()

            try Tracker.bootstrap(tracker)
            await Task.detached {
                Tracker.current.track(SignedUp(plan: "plus"))
            }.value
            let actualError: TrackerAlreadyBootstrapped?
            do throws(TrackerAlreadyBootstrapped) {
                try Tracker.bootstrap(Tracker())
                actualError = nil
            } catch {
                actualError = error
            }
            await tracker.finish()

            var actual: [String] = []
            for await record in tracker.records {
                actual.append((record.event as? SignedUp)?.plan ?? "")
            }
            guard actual == expected, actualError == expectedError else { exit(EXIT_FAILURE) }
        }
    }
}
