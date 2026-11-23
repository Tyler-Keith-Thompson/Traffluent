// Exit tests, in a file of their own: each runs its body in a child process, which iOS, tvOS,
// watchOS and visionOS cannot start.

import Destinations
import TraffluentTestSupport
import Testing

@Suite("InMemoryDestination: traps", .timeLimit(.minutes(1)))
struct InMemoryDestinationExitTests {
    @Test("A capacity below 1 traps", .tags(.precondition))
    func zeroCapacityTraps() async {
        await #expect(processExitsWith: .failure) {
            _ = InMemoryDestination(capacity: 0)
        }
    }
}
