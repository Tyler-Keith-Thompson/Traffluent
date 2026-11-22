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

    /// Never flushes; sends `started` each time a run starts it, so a test knows the run is
    /// reading.
    struct StartGate<Element>: BatchStrategy {
        let started: SingleValueSubject<Void>

        func run(_ flusher: BatchFlusher) async throws {
            try? started.send()
        }
    }

    /// Hands out 1970 plus one second, plus two, and so on: a later date each call.
    final class Ticker: Sendable {
        let calls = Mutex(0)

        func now() -> Date {
            calls.withLock {
                $0 += 1
                return Date(timeIntervalSince1970: Double($0))
            }
        }
    }

    /// Counts its runs: the first throws, a later one sends `retried`.
    struct FailsOnce<Element>: BatchStrategy {
        struct Broken: Error {}

        final class Runs: Sendable {
            let count = Mutex(0)
        }

        let runs = Runs()
        let retried: SingleValueSubject<Void>

        func run(_ flusher: BatchFlusher) async throws {
            let run = runs.count.withLock {
                $0 += 1
                return $0
            }
            guard run > 1 else { throw Broken() }
            try? retried.send()
        }
    }

    /// Holds its first batch until `gate` opens, after announcing it on `entered`; records every
    /// batch it receives.
    final class Stuck: Destination {
        let entered = SingleValueSubject<Void>()
        let gate = SingleValueSubject<Void>()
        let batches = Mutex<[[Int]]>([])

        func receive(_ batch: [EventRecord]) async {
            batches.withLock { $0.append(batch.compactMap { ($0.event as? Tapped)?.number }) }
            guard (try? entered.send()) != nil else { return }
            try? await gate.execute()
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
            strategy: .either(.time(interval: .seconds(5), clock: clock), PendingGate(count: 2, reached: twoPending)))
        let expectedFirst = [[1, 2]]
        let expected = [[1, 2], [3]]
        sut.track(Tapped(number: 1))
        sut.track(Tapped(number: 2))
        let work = sut.run()
        let running = Task { try await work.execute() }
        try await twoPending.execute()
        // The interval's sleep is registered once checkSuspension throws. swift-clocks' TestClock
        // has no way to await a sleeper, and advancing before the strategy sleeps would move the
        // interval's start past the advance, so polling (which yields, never sleeps) is the least
        // bad gate short of a hand-written clock.
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

    @Test("The default strategy delivers what is pending once 30 seconds pass on the pipeline's clock")
    func defaultInterval() async throws {
        let clock = TestClock()
        let recorder = Recorder()
        let sut = Pipeline(recorder, clock: clock)
        let expected = [[1]]
        sut.track(Tapped(number: 1))
        let work = sut.run()
        let running = Task { try await work.execute() }
        // Polled for the reason timeStrategy gives.
        while (try? await clock.checkSuspension()) != nil {}

        await clock.advance(by: .seconds(30))
        var arrivals = recorder.arrivals.makeAsyncIterator()
        _ = await arrivals.next()
        let actual = recorder.numbers
        sut.finish()
        try await running.value

        #expect(actual == expected)
    }

    @Test("The default strategy delivers 20 records as one batch without waiting for its interval")
    func defaultTwenty() async throws {
        let recorder = Recorder()
        let sut = Pipeline(recorder, clock: TestClock())
        let expected = [Array(1 ... 20)]
        let work = sut.run()
        let running = Task { try await work.execute() }

        for number in 1 ... 20 {
            sut.track(Tapped(number: number))
        }
        var arrivals = recorder.arrivals.makeAsyncIterator()
        _ = await arrivals.next()
        let actual = recorder.numbers
        sut.finish()
        try await running.value

        #expect(actual == expected)
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
    func cancelDropsPending() async throws {
        let started = SingleValueSubject<Void>()
        let recorder = Recorder()
        let sut = Pipeline(recorder, strategy: .either(.count(2), StartGate(started: started)))
        let expected: [[Int]] = []
        sut.track(Tapped(number: 1))
        let work = sut.run()
        let running = Task { try await work.execute() }
        try await started.execute()

        running.cancel()
        _ = await running.result
        sut.finish()

        #expect(recorder.numbers == expected)
    }

    @Test("After a cancelled run, the next run delivers the events tracked since")
    func runAgainAfterCancel() async throws {
        let started = SingleValueSubject<Void>()
        let recorder = Recorder()
        let sut = Pipeline(recorder, strategy: .either(.count(5), StartGate(started: started)))
        let expected = [[2, 3]]
        let first = sut.run()
        let running = Task { try await first.execute() }
        try await started.execute()
        running.cancel()
        _ = await running.result

        sut.track(Tapped(number: 2))
        sut.track(Tapped(number: 3))
        sut.finish()
        try await sut.run().execute()

        #expect(recorder.numbers == expected)
    }

    @Test("Retrying a run whose strategy failed runs again and delivers")
    func retryAfterFailure() async throws {
        let retried = SingleValueSubject<Void>()
        let recorder = Recorder()
        let sut = Pipeline(recorder, strategy: .either(.count(5), FailsOnce(retried: retried)))
        let expected = [[1]]
        let work = sut.run().retry(1)
        let running = Task { try await work.execute() }
        try await retried.execute()

        sut.track(Tapped(number: 1))
        sut.finish()
        try await running.value

        #expect(recorder.numbers == expected)
    }

    @Test("A destination that never returns doesn't hold up delivery to the others")
    func stuckDestination() async throws {
        let stuck = Stuck()
        let recorder = Recorder()
        let sut = Pipeline(stuck, recorder, strategy: .count(1))
        let expected = [[1], [2]]
        let work = sut.run()
        let running = Task { try await work.execute() }

        sut.track(Tapped(number: 1))
        sut.track(Tapped(number: 2))
        var arrivals = recorder.arrivals.makeAsyncIterator()
        _ = await arrivals.next()
        _ = await arrivals.next()
        let actual = recorder.numbers
        try stuck.gate.send()
        sut.finish()
        try await running.value

        #expect(actual == expected)
    }

    @Test("A destination that falls behind keeps the newest batches up to the buffer limit, dropping the oldest")
    func dropsOldestBatch() async throws {
        let stuck = Stuck()
        let recorder = Recorder()
        let sut = Pipeline(stuck, recorder, strategy: .count(1), batchBufferLimit: 1)
        let expected = [[1], [4]]
        let work = sut.run()
        let running = Task { try await work.execute() }
        sut.track(Tapped(number: 1))
        try await stuck.entered.execute()

        sut.track(Tapped(number: 2))
        sut.track(Tapped(number: 3))
        sut.track(Tapped(number: 4))
        // The other destination has a buffer of one too, so it may skip batches; once it has the
        // last one, every batch has been handed to the stuck destination's buffer, which is
        // handed each batch first.
        var arrivals = recorder.arrivals.makeAsyncIterator()
        while let batch = await arrivals.next(), (batch.last?.event as? Tapped)?.number != 4 {}
        try stuck.gate.send()
        sut.finish()
        try await running.value

        #expect(stuck.batches.withLock { $0 } == expected)
    }

    @Test("A strategy's error ends the run with that error")
    func strategyError() async {
        let sut = Pipeline(Recorder(), strategy: FailingStrategy<EventRecord>())

        await #expect(throws: FailingStrategy<EventRecord>.Broken()) {
            try await sut.run().execute()
        }
    }

    @Test("Each record is stamped with the wall-clock time `now` gives when its event is tracked")
    func timestamps() async throws {
        let ticker = Ticker()
        let recorder = Recorder()
        let sut = Pipeline(recorder, strategy: .count(5), now: { ticker.now() })
        let expected = [[Date(timeIntervalSince1970: 1), Date(timeIntervalSince1970: 2), Date(timeIntervalSince1970: 3)]]

        sut.track(Tapped(number: 1))
        sut.track(Tapped(number: 2))
        sut.track(Tapped(number: 3))
        sut.finish()
        try await sut.run().execute()

        let actual = recorder.batches.withLock { $0.map { $0.map(\.timestamp) } }
        #expect(actual == expected)
    }

    @Test("The default strategy's pipeline stamps records with `now` too")
    func defaultStrategyTimestamps() async throws {
        let ticker = Ticker()
        let recorder = Recorder()
        let sut = Pipeline(recorder, clock: TestClock(), now: { ticker.now() })
        let expected = [[Date(timeIntervalSince1970: 1)]]

        sut.track(Tapped(number: 1))
        sut.finish()
        try await sut.run().execute()

        let actual = recorder.batches.withLock { $0.map { $0.map(\.timestamp) } }
        #expect(actual == expected)
    }

    @Test("A pipeline with the default strategy stamps records with the system's current time by default")
    func defaultStrategyDefaultTimestamp() async throws {
        let recorder = Recorder()
        let sut = Pipeline(recorder, clock: TestClock())
        let earliest = Date.now

        sut.track(Tapped(number: 1))
        let latest = Date.now
        sut.finish()
        try await sut.run().execute()

        let actual = try #require(recorder.batches.withLock { $0.first?.first?.timestamp })
        #expect(actual >= earliest)
        #expect(actual <= latest)
    }

    @Test("By default a destination that falls behind keeps its 100 newest waiting batches")
    func defaultBufferLimit() async throws {
        let stuck = Stuck()
        let recorder = Recorder()
        let sut = Pipeline(stuck, recorder, strategy: .count(1))
        let expected = [[1]] + (3 ... 102).map { [$0] }
        let work = sut.run()
        let running = Task { try await work.execute() }
        sut.track(Tapped(number: 1))
        try await stuck.entered.execute()

        for number in 2 ... 102 {
            sut.track(Tapped(number: number))
        }
        // As in dropsOldestBatch: once the other destination has the last batch, every batch has
        // been handed to the stuck destination's buffer.
        var arrivals = recorder.arrivals.makeAsyncIterator()
        while let batch = await arrivals.next(), (batch.last?.event as? Tapped)?.number != 102 {}
        try stuck.gate.send()
        sut.finish()
        try await running.value

        #expect(stuck.batches.withLock { $0 } == expected)
    }

    @Test("By default each record is stamped with the system's current time")
    func defaultTimestamp() async throws {
        let recorder = Recorder()
        let sut = Pipeline(recorder, strategy: .count(1))
        let earliest = Date.now

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
