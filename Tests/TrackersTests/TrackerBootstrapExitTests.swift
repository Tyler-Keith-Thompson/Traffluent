// Exit tests, in a file of their own: each runs its body in a child process, which iOS, tvOS,
// watchOS and visionOS cannot start.
//
// Why child processes: `Tracker.bootstrap` sets the process's default tracker once, and nothing
// can reset it (the house rules add no reset hook for tests). Bootstrapped in the test process,
// it would change what `Tracker.current` gives every other test running beside it, and a second
// test couldn't bootstrap at all. So every test that bootstraps does it in a child process of its
// own, and no test in the test process calls `Tracker.bootstrap`. Each child checks what it sees
// and exits with a failure when it differs from what is expected.

import Foundation
import Events
import Testing
import Trackers

@Suite("Tracker.bootstrap", .timeLimit(.minutes(1)))
struct TrackerBootstrapExitTests {
    struct Tapped: Event {
        var number: Int
    }

    @Test("A detached task's Tracker.current is the bootstrapped tracker, which records what it tracks")
    func detachedTaskReachesBootstrapped() async {
        await #expect(processExitsWith: .success) {
            let tracker = Tracker()
            let expected = [1, 2]
            try Tracker.bootstrap(tracker)

            await Task.detached {
                // The same call site twice, so a call site's repeated events reach it too.
                for number in [1, 2] {
                    Tracker.current.track(Tapped(number: number))
                }
            }.value
            await tracker.finish()

            var actual: [Int] = []
            for await record in tracker.records {
                actual.append((record.event as? Tapped)?.number ?? -1)
            }
            guard actual == expected else { exit(EXIT_FAILURE) }
        }
    }

    @Test("With a tracker bootstrapped and none bound, Tracker.current is not a no-op tracker")
    func currentIsNotNoOp() async {
        await #expect(processExitsWith: .success) {
            try Tracker.bootstrap(Tracker())

            let actual = Tracker.current

            guard !actual.isNoOp, !actual.enriched(by: Enricher { _ in }).isNoOp else { exit(EXIT_FAILURE) }
        }
    }

    @Test("A withTracker binding wins over the bootstrapped tracker inside its scope, and the bootstrapped one records what is tracked outside it")
    func bindingWinsOverBootstrapped() async {
        await #expect(processExitsWith: .success) {
            let bootstrapped = Tracker()
            let bound = Tracker()
            let expectedBootstrapped = [2, 4]
            let expectedBound = [1, 3]
            try Tracker.bootstrap(bootstrapped)

            await withTracker(bound) {
                Tracker.current.track(Tapped(number: 1))
                await Task.detached {
                    Tracker.current.track(Tapped(number: 2))
                }.value
                await Task {
                    Tracker.current.track(Tapped(number: 3))
                }.value
            }
            Tracker.current.track(Tapped(number: 4))
            await bootstrapped.finish()
            await bound.finish()

            var actualBootstrapped: [Int] = []
            for await record in bootstrapped.records {
                actualBootstrapped.append((record.event as? Tapped)?.number ?? -1)
            }
            var actualBound: [Int] = []
            for await record in bound.records {
                actualBound.append((record.event as? Tapped)?.number ?? -1)
            }
            guard actualBootstrapped == expectedBootstrapped, actualBound == expectedBound else { exit(EXIT_FAILURE) }
        }
    }

    @Test("A second bootstrap throws TrackerAlreadyBootstrapped, and the first tracker stays the default")
    func secondBootstrapThrows() async {
        await #expect(processExitsWith: .success) {
            let first = Tracker()
            let second = Tracker()
            let expectedFirst = [1]
            let expectedSecond: [Int] = []
            try Tracker.bootstrap(first)

            let actualError: TrackerAlreadyBootstrapped?
            do throws(TrackerAlreadyBootstrapped) {
                try Tracker.bootstrap(second)
                actualError = nil
            } catch {
                actualError = error
            }
            Tracker.current.track(Tapped(number: 1))
            await first.finish()
            await second.finish()

            var actualFirst: [Int] = []
            for await record in first.records {
                actualFirst.append((record.event as? Tapped)?.number ?? -1)
            }
            var actualSecond: [Int] = []
            for await record in second.records {
                actualSecond.append((record.event as? Tapped)?.number ?? -1)
            }
            guard actualError == TrackerAlreadyBootstrapped(), actualFirst == expectedFirst, actualSecond == expectedSecond else { exit(EXIT_FAILURE) }
        }
    }

    @Test("Bootstrapping a no-op tracker counts as the one bootstrap: a later one throws")
    func noOpBootstrapCounts() async {
        await #expect(processExitsWith: .success) {
            try Tracker.bootstrap(.noOp)

            let actual: TrackerAlreadyBootstrapped?
            do throws(TrackerAlreadyBootstrapped) {
                try Tracker.bootstrap(Tracker())
                actual = nil
            } catch {
                actual = error
            }

            guard actual == TrackerAlreadyBootstrapped(), Tracker.current.isNoOp else { exit(EXIT_FAILURE) }
        }
    }
}
