import Destinations
import Events
import Pipelines
import Synchronization
import Testing
import Trackers

@Suite("Tracker", .timeLimit(.minutes(1)))
struct TrackerTests {
    struct Tapped: Event {
        var number: Int
    }

    /// Records the number of every `Tapped` it receives, in order.
    final class Recorder: Destination {
        let numbers = Mutex<[Int]>([])

        func receive(_ batch: [EventRecord]) async {
            numbers.withLock { $0.append(contentsOf: batch.compactMap { ($0.event as? Tapped)?.number }) }
        }
    }

    /// Records every record it receives, in order.
    final class RecordRecorder: Destination {
        let records = Mutex<[EventRecord]>([])

        func receive(_ batch: [EventRecord]) async {
            records.withLock { $0.append(contentsOf: batch) }
        }
    }

    struct Rejected: Error, Equatable {}

    @Test("A tracker hands each event to its pipeline")
    func tracks() async throws {
        let recorder = Recorder()
        let pipeline = Pipeline(recorder)
        let sut = Tracker(pipeline)
        let expected = [1, 2]

        sut.track(Tapped(number: 1))
        sut.track(Tapped(number: 2))
        pipeline.finish()
        try await pipeline.run().execute()

        let actual = recorder.numbers.withLock { $0 }
        #expect(actual == expected)
    }

    @Test("A tracker records its caller's source location, not its own")
    func sourceLocation() async throws {
        let recorder = RecordRecorder()
        let pipeline = Pipeline(recorder)
        let sut = Tracker(pipeline)
        let expectedFileID = #fileID
        let expectedFunction = #function
        let expectedLine = #line + 2

        sut.track(Tapped(number: 1))
        pipeline.finish()
        try await pipeline.run().execute()

        let actual = try #require(recorder.records.withLock { $0.first }).sourceLocation
        #expect(actual.fileID == expectedFileID)
        #expect(actual.function == expectedFunction)
        #expect(actual.line == expectedLine)
    }

    @Test("Tracker.current inside withTracker is the bound tracker")
    func boundSync() async throws {
        let recorder = Recorder()
        let pipeline = Pipeline(recorder)
        let expected = [1]

        withTracker(Tracker(pipeline)) {
            Tracker.current.track(Tapped(number: 1))
        }
        pipeline.finish()
        try await pipeline.run().execute()

        let actual = recorder.numbers.withLock { $0 }
        #expect(actual == expected)
    }

    @Test("Tracker.current inside the async withTracker is the bound tracker")
    func boundAsync() async throws {
        let recorder = Recorder()
        let pipeline = Pipeline(recorder)
        let expected = [1]

        await withTracker(Tracker(pipeline)) {
            await Task.yield()
            Tracker.current.track(Tapped(number: 1))
        }
        pipeline.finish()
        try await pipeline.run().execute()

        let actual = recorder.numbers.withLock { $0 }
        #expect(actual == expected)
    }

    @Test("With no tracker bound, Tracker.current drops every event without trapping")
    func unbound() async throws {
        let recorder = Recorder()
        let pipeline = Pipeline(recorder)
        let expected: [Int] = []

        Tracker.current.track(Tapped(number: 1))
        Tracker.noOp.track(Tapped(number: 2))
        pipeline.finish()
        try await pipeline.run().execute()

        let actual = recorder.numbers.withLock { $0 }
        #expect(actual == expected)
    }

    @Test("A child task inherits the bound tracker")
    func childTask() async throws {
        let recorder = Recorder()
        let pipeline = Pipeline(recorder)
        let expected = [1, 2]

        await withTracker(Tracker(pipeline)) {
            await Task { Tracker.current.track(Tapped(number: 1)) }.value
            await withDiscardingTaskGroup { group in
                group.addTask { Tracker.current.track(Tapped(number: 2)) }
            }
        }
        pipeline.finish()
        try await pipeline.run().execute()

        let actual = recorder.numbers.withLock { $0 }
        #expect(actual == expected)
    }

    @Test("A nested withTracker replaces the binding inside its scope only")
    func nested() async throws {
        let outer = Recorder()
        let inner = Recorder()
        let outerPipeline = Pipeline(outer)
        let innerPipeline = Pipeline(inner)
        let expectedOuter = [1, 3]
        let expectedInner = [2]

        withTracker(Tracker(outerPipeline)) {
            Tracker.current.track(Tapped(number: 1))
            withTracker(Tracker(innerPipeline)) {
                Tracker.current.track(Tapped(number: 2))
            }
            Tracker.current.track(Tapped(number: 3))
        }
        outerPipeline.finish()
        innerPipeline.finish()
        try await outerPipeline.run().execute()
        try await innerPipeline.run().execute()

        let actualOuter = outer.numbers.withLock { $0 }
        let actualInner = inner.numbers.withLock { $0 }
        #expect(actualOuter == expectedOuter)
        #expect(actualInner == expectedInner)
    }

    @Test("The binding ends when withTracker returns")
    func scopeEnds() async throws {
        let recorder = Recorder()
        let pipeline = Pipeline(recorder)
        let expected = [1]

        withTracker(Tracker(pipeline)) {
            Tracker.current.track(Tapped(number: 1))
        }
        Tracker.current.track(Tapped(number: 2))
        pipeline.finish()
        try await pipeline.run().execute()

        let actual = recorder.numbers.withLock { $0 }
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
