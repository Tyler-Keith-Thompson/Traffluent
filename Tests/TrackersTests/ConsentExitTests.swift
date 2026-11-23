// Exit tests, in a file of their own: each runs its body in a child process, which iOS, tvOS,
// watchOS and visionOS cannot start.

import TraffluentTestSupport
import Testing
import Trackers

@Suite("Consent: traps", .timeLimit(.minutes(1)))
struct ConsentExitTests {
    @Test("A negative held record limit traps", .tags(.precondition))
    func negativeLimitTraps() async {
        await #expect(processExitsWith: .failure) {
            _ = Consent(heldRecordLimit: -1)
        }
    }
}
