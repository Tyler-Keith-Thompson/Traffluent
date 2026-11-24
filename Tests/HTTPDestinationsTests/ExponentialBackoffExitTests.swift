// Exit tests, in a file of their own: each runs its body in a child process, which iOS, tvOS,
// watchOS and visionOS cannot start.

import HTTPDestinations
import TraffluentTestSupport
import Testing

@Suite("ExponentialBackoff: traps", .timeLimit(.minutes(1)))
struct ExponentialBackoffExitTests {
    @Test("An initial delay of zero traps", .tags(.precondition))
    func zeroInitialTraps() async {
        await #expect(processExitsWith: .failure) {
            _ = ExponentialBackoff(initialDelay: .zero, maximumDelay: .seconds(1))
        }
    }

    @Test("A negative initial delay traps", .tags(.precondition))
    func negativeInitialTraps() async {
        await #expect(processExitsWith: .failure) {
            _ = ExponentialBackoff(initialDelay: .seconds(-1), maximumDelay: .seconds(1))
        }
    }

    @Test("A maximum delay less than the initial one traps", .tags(.precondition))
    func maximumBelowInitialTraps() async {
        await #expect(processExitsWith: .failure) {
            _ = ExponentialBackoff(initialDelay: .seconds(2), maximumDelay: .seconds(1))
        }
    }

    @Test("A retry numbered below 1 traps", .tags(.precondition))
    func retryZeroTraps() async {
        await #expect(processExitsWith: .failure) {
            _ = ExponentialBackoff().delay(beforeRetry: 0)
        }
    }
}
