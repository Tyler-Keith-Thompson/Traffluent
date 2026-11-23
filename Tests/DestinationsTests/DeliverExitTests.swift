// Exit tests, in a file of their own: each runs its body in a child process, which iOS, tvOS,
// watchOS and visionOS cannot start.

import Destinations
import TraffluentTestSupport
import Testing
import Trackers

@Suite("deliver(to:): traps", .timeLimit(.minutes(1)))
struct DeliverExitTests {
    @Test("A batch buffer limit below 1 traps", .tags(.precondition))
    func zeroBufferLimitTraps() async {
        await #expect(processExitsWith: .failure) {
            _ = Tracker().records.batch(strategy: .count(1)).deliver(batchBufferLimit: 0)
        }
    }
}
