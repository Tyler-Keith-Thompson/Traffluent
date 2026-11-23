// Exit tests, in a file of their own: each runs its body in a child process, which iOS, tvOS,
// watchOS and visionOS cannot start.

import Testing
import Trackers
import TraffluentTestSupport

@Suite("Sampling: traps", .timeLimit(.minutes(1)))
struct SamplingExitTests {
    @Test("A sample rate above 1 traps", .tags(.precondition))
    func aboveOneTraps() async {
        await #expect(processExitsWith: .failure) {
            _ = SampleRate(1.5)
        }
    }

    @Test("A sample rate below 0 traps", .tags(.precondition))
    func belowZeroTraps() async {
        await #expect(processExitsWith: .failure) {
            _ = SampleRate(-0.1)
        }
    }

    @Test("A NaN sample rate traps", .tags(.precondition))
    func nanTraps() async {
        await #expect(processExitsWith: .failure) {
            _ = SampleRate(.nan)
        }
    }

    @Test("An integer literal other than 0 or 1 traps as a sample rate", .tags(.precondition))
    func integerLiteralTraps() async {
        await #expect(processExitsWith: .failure) {
            let rate: SampleRate = 2
            _ = rate
        }
    }
}
