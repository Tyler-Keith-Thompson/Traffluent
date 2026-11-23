// Exit tests, in a file of their own: each runs its body in a child process, which iOS, tvOS,
// watchOS and visionOS cannot start.

import Sessions
import Testing
import Trackers
import TraffluentTestSupport

@Suite("Sessions: traps", .timeLimit(.minutes(1)))
struct SessionExitTests {
    @Test("A timeout of zero traps", .tags(.precondition))
    func zeroTimeoutTraps() async {
        await #expect(processExitsWith: .failure) {
            _ = Enricher.sessions(timeout: .zero)
        }
    }

    @Test("A negative timeout traps", .tags(.precondition))
    func negativeTimeoutTraps() async {
        await #expect(processExitsWith: .failure) {
            _ = Enricher.sessions(timeout: .seconds(-1))
        }
    }
}
