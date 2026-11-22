import Afluent
import Clocks
import Destinations
import Events
import Foundation
import Pipelines
import Synchronization
import Testing

@Suite("Pipeline", .timeLimit(.minutes(1)))
struct PipelineTests {
    struct Tapped: Event {
        var number: Int
    }

    /// Records every batch it receives, and announces each one on `arrivals`.
    final class Recorder: Destination {
        let batches = Mutex<[[EventRecord]]>([])
        let (arrivals, continuation) = AsyncStream.makeStream(of: [EventRecord].self)

        func receive(_ batch: [EventRecord]) async {
            batches.withLock { $0.append(batch) }
            continuation.yield(batch)
        }

        /// The numbers of the `Tapped` events received, batch by batch.
        var numbers: [[Int]] {
            batches.withLock { $0.map { $0.compactMap { ($0.event as? Tapped)?.number } } }
        }
    }

    /// Never flushes; sends `reached` once `count` records are pending, so a test knows the
    /// pipeline has them before it moves a clock.
    struct PendingGate: BatchStrategy {
        let count: Int
        let reached: SingleValueSubject<Void>

        func flushes(pending: [EventRecord]) -> Bool {
            if pending.count == count {
                try? reached.send()
            }
            return false
        }
    }

    /// Fails as soon as it runs.
    struct FailingStrategy<Element>: BatchStrategy {
        struct Broken: Error, Equatable {}

        func run(_ flusher: BatchFlusher) async throws {
            throw Broken()
        }
    }

    @Test("A count strategy delivers full batches, then the remainder when the pipeline finishes")
    func countStrategy() async throws {
        let recorder = Recorder()
        let sut = Pipeline(recorder, strategy: .count(2))
        let expected = [[1, 2], [3, 4], [5]]

        for number in 1 ... 5 {
            sut.track(Tapped(number: number))
        }
        sut.finish()
        try await sut.run().execute()

        #expect(recorder.numbers == expected)
    }

    @Test("A time strategy delivers the pending records when its interval passes on its clock")
    func timeStrategy() async throws {
        let clock = TestClock()
        let twoPending = SingleValueSubject<Void>()
        let recorder = Recorder()
        let sut = Pipeline(
            recorder,
            clock: clock,
            strategy: .either(.time(interval: .seconds(5), clock: clock), PendingGate(count: 2, reached: twoPending)))
        let expectedFirst = [[1, 2]]
        let expected = [[1, 2], [3]]
        sut.track(Tapped(number: 1))
        sut.track(Tapped(number: 2))
        let work = sut.run()
        let running = Task { try await work.execute() }
        try await twoPending.execute()
        // The interval's sleep is registered once checkSuspension throws.
        while (try? await clock.checkSuspension()) != nil {}

        await clock.advance(by: .seconds(5))
        var arrivals = recorder.arrivals.makeAsyncIterator()
        _ = await arrivals.next()
        let actualFirst = recorder.numbers
        sut.track(Tapped(number: 3))
        sut.finish()
        try await running.value

        #expect(actualFirst == expectedFirst)
        #expect(recorder.numbers == expected)
    }

    @Test("The default strategy delivers every 20 records as a batch")
    func defaultCount() async throws {
        let recorder = Recorder()
        let sut = Pipeline(recorder, clock: TestClock())
        let expected = [Array(1 ... 20), Array(21 ... 40), [41]]

        for number in 1 ... 41 {
            sut.track(Tapped(number: number))
        }
        sut.finish()
        try await sut.run().execute()

        #expect(recorder.numbers == expected)
    }

    @Test("The default strategy is 20 records or 30 seconds on the pipeline's clock, whichever comes first")
    func defaultStrategy() throws {
        let clock = TestClock()
        let expectedCount = 20
        let expectedInterval = Duration.seconds(30)
        let expectedStrategies = 2

        let sut = Pipeline(clock: clock)

        let either = try #require(sut.strategy as? EitherBatchStrategy<EventRecord>)
        let count = try #require(either.strategies.first as? CountBatchStrategy<EventRecord>)
        let time = try #require(either.strategies.last as? TimeBatchStrategy<EventRecord, TestClock<Duration>>)
        #expect(either.strategies.count == expectedStrategies)
        #expect(count.count == expectedCount)
        #expect(time.interval == expectedInterval)
        #expect(time.clock === clock)
        #expect(time.tolerance == nil)
    }

    @Test("Every destination receives the same batches, in the same order")
    func fanOut() async throws {
        let first = Recorder()
        let second = Recorder()
        let sut = Pipeline(first, second, strategy: .count(2))
        let expected = [[1, 2], [3]]

        sut.track(Tapped(number: 1))
        sut.track(Tapped(number: 2))
        sut.track(Tapped(number: 3))
        sut.finish()
        try await sut.run().execute()

        #expect(first.numbers == expected)
        #expect(second.numbers == expected)
    }

    @Test("A pipeline that tracks nothing delivers no batch, not an empty one")
    func empty() async throws {
        let recorder = Recorder()
        let sut = Pipeline(recorder, strategy: .count(2))
        let expected: [[Int]] = []

        sut.finish()
        try await sut.run().execute()

        #expect(recorder.numbers == expected)
    }

    @Test("One tracked event is delivered as a batch of one when the pipeline finishes")
    func oneEvent() async throws {
        let recorder = Recorder()
        let sut = Pipeline(recorder, strategy: .count(2))
        let expected = [[7]]

        sut.track(Tapped(number: 7))
        sut.finish()
        try await sut.run().execute()

        #expect(recorder.numbers == expected)
    }

    @Test("A pipeline with no destinations accepts events and finishes")
    func noDestinations() async throws {
        let sut = Pipeline(strategy: .count(1))

        sut.track(Tapped(number: 1))
        sut.finish()
        try await sut.run().execute()
    }

    @Test("An event tracked after finish is dropped")
    func trackAfterFinish() async throws {
        let recorder = Recorder()
        let sut = Pipeline(recorder, strategy: .count(5))
        let expected = [[1]]

        sut.track(Tapped(number: 1))
        sut.finish()
        sut.track(Tapped(number: 2))
        try await sut.run().execute()

        #expect(recorder.numbers == expected)
    }

    @Test("Copies of a pipeline share one stream of events")
    func copiesShare() async throws {
        let recorder = Recorder()
        let sut = Pipeline(recorder, strategy: .count(5))
        let copy = sut
        let expected = [[1, 2]]

        sut.track(Tapped(number: 1))
        copy.track(Tapped(number: 2))
        copy.finish()
        try await sut.run().execute()

        #expect(recorder.numbers == expected)
    }

    @Test("Cancelling the run delivers none of the pending records")
    func cancelDropsPending() async {
        let recorder = Recorder()
        let sut = Pipeline(recorder, strategy: .count(2))
        let expected: [[Int]] = []
        sut.track(Tapped(number: 1))
        let work = sut.run()
        let running = Task { try await work.execute() }

        running.cancel()
        _ = await running.result
        sut.finish()

        #expect(recorder.numbers == expected)
    }

    @Test("A strategy's error ends the run with that error")
    func strategyError() async {
        let sut = Pipeline(Recorder(), strategy: FailingStrategy<EventRecord>())

        await #expect(throws: FailingStrategy<EventRecord>.Broken()) {
            try await sut.run().execute()
        }
    }

    @Test("A record's timestamp is the pipeline's creation time plus how far its clock has advanced")
    func timestamps() async throws {
        let clock = TestClock()
        let recorder = Recorder()
        let earliest = Date.now
        let sut = Pipeline(recorder, clock: clock, strategy: .count(5))
        let latest = Date.now
        let expectedGaps: [TimeInterval] = [0, 2.5, 4]

        sut.track(Tapped(number: 1))
        await clock.advance(by: .milliseconds(2500))
        sut.track(Tapped(number: 2))
        await clock.advance(by: .milliseconds(1500))
        sut.track(Tapped(number: 3))
        sut.finish()
        try await sut.run().execute()

        let actual = recorder.batches.withLock { $0.flatMap { $0.map(\.timestamp) } }
        let origin = try #require(actual.first)
        #expect(origin >= earliest)
        #expect(origin <= latest)
        #expect(actual.map { $0.timeIntervalSince(origin) } == expectedGaps)
    }

    @Test("By default timestamps follow the continuous clock from the pipeline's creation")
    func defaultClockTimestamp() async throws {
        let recorder = Recorder()
        let earliest = Date.now
        let sut = Pipeline(recorder, strategy: .count(1))

        sut.track(Tapped(number: 1))
        let latest = Date.now
        sut.finish()
        try await sut.run().execute()

        let actual = try #require(recorder.batches.withLock { $0.first?.first?.timestamp })
        #expect(actual >= earliest)
        #expect(actual <= latest)
    }

    @Test("A record carries its event, with the event's type and value")
    func event() async throws {
        let recorder = Recorder()
        let sut = Pipeline(recorder, strategy: .count(1))
        let expectedName = "Tapped"
        let expectedNumber = 9

        sut.track(Tapped(number: expectedNumber))
        sut.finish()
        try await sut.run().execute()

        let record = try #require(recorder.batches.withLock { $0.first?.first })
        let event = try #require(record.event as? Tapped)
        #expect(record.name == expectedName)
        #expect(event.number == expectedNumber)
    }

    @Test("Tracking captures the caller's file, file ID, module, function, line and column")
    func capturedSourceLocation() async throws {
        let recorder = Recorder()
        let sut = Pipeline(recorder, strategy: .count(1))
        // In the Swift 6 language mode `#file` is the file ID.
        let expectedFile = "PipelinesTests/PipelineTests.swift"
        let expectedFileID = "PipelinesTests/PipelineTests.swift"
        let expectedModule = "PipelinesTests"
        let expectedFunction = "capturedSourceLocation()"
        // `#column` as a default argument is the column of the call's opening parenthesis.
        let expectedColumn = 18
        let expectedLine = #line + 2

        sut.track(Tapped(number: 1))
        sut.finish()
        try await sut.run().execute()

        let record = try #require(recorder.batches.withLock { $0.first?.first })
        #expect(record.sourceLocation.file == expectedFile)
        #expect(record.sourceLocation.fileID == expectedFileID)
        #expect(record.sourceLocation.moduleName == expectedModule)
        #expect(record.sourceLocation.function == expectedFunction)
        #expect(record.sourceLocation.line == expectedLine)
        #expect(record.sourceLocation.column == expectedColumn)
    }

    @Test("A source location passed explicitly is recorded field for field")
    func explicitSourceLocation() async throws {
        let recorder = Recorder()
        let sut = Pipeline(recorder, strategy: .count(1))
        let expected = Events.SourceLocation(file: "/src/App/Cart.swift", fileID: "App/Cart.swift", function: "pay()", line: 41, column: 7)

        sut.track(Tapped(number: 1), file: "/src/App/Cart.swift", fileID: "App/Cart.swift", function: "pay()", line: 41, column: 7)
        sut.finish()
        try await sut.run().execute()

        let actual = try #require(recorder.batches.withLock { $0.first?.first?.sourceLocation })
        #expect(actual == expected)
    }
}
