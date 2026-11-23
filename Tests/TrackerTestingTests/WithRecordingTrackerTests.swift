import Events
import Testing
import TrackerTesting
import Trackers

@Suite("withRecordingTracker", .timeLimit(.minutes(1)))
struct WithRecordingTrackerTests {
    struct SignedUp: Event, Equatable {
        var plan: String
    }

    struct Viewed: Event, Equatable {
        var number: Int
    }

    struct Failed: Error, Equatable {}

    @Test("A sync body's events, tracked through Tracker.current, are recorded in the order tracked")
    func syncBody() async {
        let expected = [SignedUp(plan: "free"), SignedUp(plan: "pro")]

        let actual = await withRecordingTracker {
            Tracker.current.track(SignedUp(plan: "free"))
            Tracker.current.track(SignedUp(plan: "pro"))
        }

        #expect(actual.events(of: SignedUp.self) == expected)
    }

    @Test("An async body's events, tracked across suspensions and in child tasks, are recorded")
    func asyncBody() async {
        let expected = [Viewed(number: 0), Viewed(number: 1), Viewed(number: 2)]

        let actual = await withRecordingTracker {
            Tracker.current.track(Viewed(number: 0))
            await Task.yield()
            async let child: Void = Tracker.current.track(Viewed(number: 1))
            await child
            Tracker.current.track(Viewed(number: 2))
        }

        #expect(actual.events(of: Viewed.self) == expected)
    }

    @Test("A sync body given the tracker records what it tracks through it and through Tracker.current alike")
    func syncBodyGivenTheTracker() async {
        let expected = [Viewed(number: 0), Viewed(number: 1)]

        let actual = await withRecordingTracker { tracker in
            tracker.track(Viewed(number: 0))
            Tracker.current.track(Viewed(number: 1))
        }

        #expect(actual.events(of: Viewed.self) == expected)
    }

    @Test("An async body given the tracker records what it tracks through it and through Tracker.current alike")
    func asyncBodyGivenTheTracker() async {
        let expected = [Viewed(number: 0), Viewed(number: 1)]

        let actual = await withRecordingTracker { tracker in
            tracker.track(Viewed(number: 0))
            await Task.yield()
            Tracker.current.track(Viewed(number: 1))
        }

        #expect(actual.events(of: Viewed.self) == expected)
    }

    @Test("A body that tracks nothing records nothing")
    func emptyBody() async {
        let actual = await withRecordingTracker {}

        #expect(actual.records.isEmpty)
    }

    @Test("What a sync body returns is the recording's value")
    func syncValue() async {
        let expected = 42

        let actual = await withRecordingTracker { () -> Int in
            Tracker.current.track(Viewed(number: 0))
            return 42
        }

        #expect(actual.value == expected)
    }

    @Test("What an async body returns is the recording's value")
    func asyncValue() async {
        let expected = "done"

        let actual = await withRecordingTracker { tracker async -> String in
            await Task.yield()
            tracker.track(Viewed(number: 0))
            return "done"
        }

        #expect(actual.value == expected)
    }

    @Test("A sync body's typed error is rethrown")
    func syncThrows() async {
        func sut() async throws(Failed) -> TrackerRecording<Void> {
            try await withRecordingTracker { () throws(Failed) in
                Tracker.current.track(Viewed(number: 0))
                throw Failed()
            }
        }

        await #expect(throws: Failed()) { try await sut() }
    }

    @Test("An async body's typed error is rethrown")
    func asyncThrows() async {
        func sut() async throws(Failed) -> TrackerRecording<Void> {
            try await withRecordingTracker { () async throws(Failed) in
                await Task.yield()
                throw Failed()
            }
        }

        await #expect(throws: Failed()) { try await sut() }
    }

    @Test("A nested recording takes only its own body's events, and the outer binding is restored after it")
    func nested() async {
        let expectedOuter = [Viewed(number: 0), Viewed(number: 2)]
        let expectedInner = [Viewed(number: 1)]

        var inner: TrackerRecording<Void>?
        let outer = await withRecordingTracker {
            Tracker.current.track(Viewed(number: 0))
            inner = await withRecordingTracker {
                Tracker.current.track(Viewed(number: 1))
            }
            Tracker.current.track(Viewed(number: 2))
        }

        #expect(outer.events(of: Viewed.self) == expectedOuter)
        #expect(inner?.events(of: Viewed.self) == expectedInner)
    }

    @Test("Once the recording returns, its tracker is no longer bound")
    func unboundAfterwards() async {
        let tracked = await withRecordingTracker {}
        _ = tracked

        var actual: [EventRecord] = []
        for await record in Tracker.current.records {
            actual.append(record)
        }

        #expect(actual.isEmpty)
    }

    @Test("Each call gets a fresh tracker, so a second recording holds none of the first's events")
    func freshTrackerPerCall() async {
        let expected = [Viewed(number: 1)]

        _ = await withRecordingTracker {
            Tracker.current.track(Viewed(number: 0))
        }
        let actual = await withRecordingTracker {
            Tracker.current.track(Viewed(number: 1))
        }

        #expect(actual.events(of: Viewed.self) == expected)
    }

    @Test("An event tracked through a kept copy after the body returns is not recorded, and the recording still ends")
    func trackedAfterwards() async {
        let expected = [Viewed(number: 0)]

        let actual = await withRecordingTracker { tracker -> Tracker in
            tracker.track(Viewed(number: 0))
            return tracker
        }
        actual.value.track(Viewed(number: 1))

        #expect(actual.events(of: Viewed.self) == expected)
    }

    @Test("Recordings running at once each see only their own events")
    func concurrentRecordings() async {
        let tasks = 64
        let eventsPerTask = 20

        let actual = await withTaskGroup(of: (Int, [Viewed]).self) { group in
            for task in 0 ..< tasks {
                group.addTask {
                    let recording = await withRecordingTracker {
                        for event in 0 ..< eventsPerTask {
                            Tracker.current.track(Viewed(number: task * 1_000 + event))
                            if event.isMultiple(of: 5) { await Task.yield() }
                        }
                    }
                    return (task, recording.events(of: Viewed.self))
                }
            }
            var recorded: [Int: [Viewed]] = [:]
            for await (task, events) in group {
                recorded[task] = events
            }
            return recorded
        }

        #expect(actual.count == tasks)
        for task in actual.keys.sorted() {
            let expected = (0 ..< eventsPerTask).map { Viewed(number: task * 1_000 + $0) }
            #expect(actual[task] == expected)
        }
    }
}
