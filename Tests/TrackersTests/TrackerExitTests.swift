// Exit tests, in a file of their own: each runs its body in a child process, which iOS, tvOS,
// watchOS and visionOS cannot start.

import TraffluentTestSupport
import Testing
import Trackers

@Suite("Tracker: traps", .timeLimit(.minutes(1)))
struct TrackerExitTests {
    @Test("Reading a tracker's records from a second task while a read is waiting traps", .tags(.precondition))
    func concurrentReadsTrap() async {
        await #expect(processExitsWith: .failure) {
            // Nothing is tracked or finished, so whichever read starts first waits for ever and
            // the other one traps.
            let sut = Tracker()
            async let first: Void = {
                var records = sut.records.makeAsyncIterator()
                _ = await records.next()
            }()

            var second = sut.records.makeAsyncIterator()
            _ = await second.next()
            await first
        }
    }
}
