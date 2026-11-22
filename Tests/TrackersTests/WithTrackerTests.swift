import Events
import Testing
import Trackers

@Suite("withTracker and Tracker.current", .timeLimit(.minutes(1)))
struct WithTrackerTests {
    struct Tapped: Event {
        var number: Int
    }

    struct Rejected: Error, Equatable {}

    @Test("Tracker.current inside withTracker is the bound tracker")
    func boundSync() async {
        let tracker = Tracker()
        let expected = [1]

        withTracker(tracker) {
            Tracker.current.track(Tapped(number: 1))
        }
        tracker.finish()

        var actual: [Int] = []
        for await record in tracker.records {
            actual.append((record.event as? Tapped)?.number ?? -1)
        }
        #expect(actual == expected)
    }

    @Test("Tracker.current inside the async withTracker is the bound tracker")
    func boundAsync() async {
        let tracker = Tracker()
        let expected = [1]

        await withTracker(tracker) {
            await Task.yield()
            Tracker.current.track(Tapped(number: 1))
        }
        tracker.finish()

        var actual: [Int] = []
        for await record in tracker.records {
            actual.append((record.event as? Tapped)?.number ?? -1)
        }
        #expect(actual == expected)
    }

    @Test("With no tracker bound, Tracker.current drops every event without trapping")
    func unbound() async {
        let tracker = Tracker()
        let expected: [Int] = []

        Tracker.current.track(Tapped(number: 1))
        Tracker.noOp.track(Tapped(number: 2))
        tracker.finish()

        var actual: [Int] = []
        for await record in tracker.records {
            actual.append((record.event as? Tapped)?.number ?? -1)
        }
        #expect(actual == expected)
    }

    @Test("A child task inherits the bound tracker")
    func childTask() async {
        let tracker = Tracker()
        let expected = [1, 2]

        await withTracker(tracker) {
            await Task { Tracker.current.track(Tapped(number: 1)) }.value
            await withDiscardingTaskGroup { group in
                group.addTask { Tracker.current.track(Tapped(number: 2)) }
            }
        }
        tracker.finish()

        var actual: [Int] = []
        for await record in tracker.records {
            actual.append((record.event as? Tapped)?.number ?? -1)
        }
        #expect(actual == expected)
    }

    @Test("A nested withTracker replaces the binding inside its scope only")
    func nested() async {
        let outer = Tracker()
        let inner = Tracker()
        let expectedOuter = [1, 3]
        let expectedInner = [2]

        withTracker(outer) {
            Tracker.current.track(Tapped(number: 1))
            withTracker(inner) {
                Tracker.current.track(Tapped(number: 2))
            }
            Tracker.current.track(Tapped(number: 3))
        }
        outer.finish()
        inner.finish()

        var actualOuter: [Int] = []
        for await record in outer.records {
            actualOuter.append((record.event as? Tapped)?.number ?? -1)
        }
        var actualInner: [Int] = []
        for await record in inner.records {
            actualInner.append((record.event as? Tapped)?.number ?? -1)
        }
        #expect(actualOuter == expectedOuter)
        #expect(actualInner == expectedInner)
    }

    @Test("The binding ends when withTracker returns")
    func scopeEnds() async {
        let tracker = Tracker()
        let expected = [1]

        withTracker(tracker) {
            Tracker.current.track(Tapped(number: 1))
        }
        Tracker.current.track(Tapped(number: 2))
        tracker.finish()

        var actual: [Int] = []
        for await record in tracker.records {
            actual.append((record.event as? Tapped)?.number ?? -1)
        }
        #expect(actual == expected)
    }

    @Test("withTracker returns what its operation returns")
    func returns() async {
        let expected = 42

        let actualSync = withTracker(.noOp) { 42 }
        let actualAsync = await withTracker(.noOp) { () async -> Int in 42 }

        #expect(actualSync == expected)
        #expect(actualAsync == expected)
    }

    @Test("withTracker throws its operation's typed error")
    func throwsTyped() async {
        func syncBody() throws(Rejected) -> Int { throw Rejected() }
        func asyncBody() async throws(Rejected) -> Int { throw Rejected() }

        #expect(throws: Rejected()) { try withTracker(.noOp, syncBody) }
        await #expect(throws: Rejected()) { try await withTracker(.noOp, asyncBody) }
    }
}
