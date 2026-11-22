import Afluent
import Clocks
import DestinationTesting
import Destinations
import Events
import Foundation
import Synchronization
import Testing
import Trackers

@Suite("deliver(to:)", .timeLimit(.minutes(1)))
struct DeliverTests {
    struct Tapped: Event {
        var number: Int
    }

    /// Never flushes; sends `reached` once `count` records are pending, so a test knows the
    /// batch has them before it moves a clock.
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

    /// Never flushes; sends `started` each time a delivery starts it, so a test knows the
    /// delivery is reading.
    struct StartGate<Element>: BatchStrategy {
        let started: SingleValueSubject<Void>

        func run(_ flusher: BatchFlusher) async throws {
            try? started.send()
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

    @Test("A count strategy delivers full batches, then the remainder when the tracker finishes")
    func countStrategy() async throws {
        let recorder = InMemoryDestination()
        let tracker = Tracker()
        let sut = tracker.records.batch(strategy: .count(2)).deliver(to: recorder)
        let expected = [[1, 2], [3, 4], [5]]

        for number in 1 ... 5 {
            tracker.track(Tapped(number: number))
        }
        tracker.finish()
        try await sut.execute()

        #expect(recorder.numbers == expected)
    }

    @Test("A time strategy delivers the pending records when its interval passes on its clock")
    func timeStrategy() async throws {
        let clock = TestClock()
        let twoPending = SingleValueSubject<Void>()
        let recorder = InMemoryDestination()
        let tracker = Tracker()
        let sut = tracker.records
            .batch(strategy: .either(.time(interval: .seconds(5), clock: clock), PendingGate(count: 2, reached: twoPending)))
            .deliver(to: recorder)
        let expectedFirst = [[1, 2]]
        let expected = [[1, 2], [3]]
        tracker.track(Tapped(number: 1))
        tracker.track(Tapped(number: 2))
        let running = Task { try await sut.execute() }
        try await twoPending.execute()
        // The interval's sleep is registered once checkSuspension throws. swift-clocks' TestClock
        // has no way to await a sleeper, and advancing before the strategy sleeps would move the
        // interval's start past the advance, so polling (which yields, never sleeps) is the least
        // bad gate short of a hand-written clock.
        while (try? await clock.checkSuspension()) != nil {}

        await clock.advance(by: .seconds(5))
        var deliveries = recorder.deliveries.makeAsyncIterator()
        _ = await deliveries.next()
        let actualFirst = recorder.numbers
        tracker.track(Tapped(number: 3))
        tracker.finish()
        try await running.value

        #expect(actualFirst == expectedFirst)
        #expect(recorder.numbers == expected)
    }

    @Test("The default batching delivers every 20 records as a batch")
    func defaultCount() async throws {
        let recorder = InMemoryDestination()
        let tracker = Tracker()
        let sut = tracker.records.batch(clock: TestClock()).deliver(to: recorder)
        let expected = [Array(1 ... 20), Array(21 ... 40), [41]]

        for number in 1 ... 41 {
            tracker.track(Tapped(number: number))
        }
        tracker.finish()
        try await sut.execute()

        #expect(recorder.numbers == expected)
    }

    @Test("The default batching delivers what is pending once 30 seconds pass on its clock")
    func defaultInterval() async throws {
        let clock = TestClock()
        let recorder = InMemoryDestination()
        let tracker = Tracker()
        let sut = tracker.records.batch(clock: clock).deliver(to: recorder)
        let expected = [[1]]
        tracker.track(Tapped(number: 1))
        let running = Task { try await sut.execute() }
        // Polled for the reason timeStrategy gives.
        while (try? await clock.checkSuspension()) != nil {}

        await clock.advance(by: .seconds(30))
        var deliveries = recorder.deliveries.makeAsyncIterator()
        _ = await deliveries.next()
        let actual = recorder.numbers
        tracker.finish()
        try await running.value

        #expect(actual == expected)
    }

    @Test("The default batching delivers 20 records as one batch without waiting for its interval")
    func defaultTwenty() async throws {
        let recorder = InMemoryDestination()
        let tracker = Tracker()
        let sut = tracker.records.batch(clock: TestClock()).deliver(to: recorder)
        let expected = [Array(1 ... 20)]
        let running = Task { try await sut.execute() }

        for number in 1 ... 20 {
            tracker.track(Tapped(number: number))
        }
        var deliveries = recorder.deliveries.makeAsyncIterator()
        _ = await deliveries.next()
        let actual = recorder.numbers
        tracker.finish()
        try await running.value

        #expect(actual == expected)
    }

    @Test("Every destination receives the same batches, in the same order")
    func fanOut() async throws {
        let first = InMemoryDestination()
        let second = InMemoryDestination()
        let tracker = Tracker()
        let sut = tracker.records.batch(strategy: .count(2)).deliver(to: first, second)
        let expected = [[1, 2], [3]]

        tracker.track(Tapped(number: 1))
        tracker.track(Tapped(number: 2))
        tracker.track(Tapped(number: 3))
        tracker.finish()
        try await sut.execute()

        #expect(first.numbers == expected)
        #expect(second.numbers == expected)
    }

    @Test("A sequence that ends with no records delivers no batch, not an empty one")
    func empty() async throws {
        let recorder = InMemoryDestination()
        let tracker = Tracker()
        let sut = tracker.records.batch(strategy: .count(2)).deliver(to: recorder)
        let expected: [[Int]] = []

        tracker.finish()
        try await sut.execute()

        #expect(recorder.numbers == expected)
    }

    @Test("One tracked event is delivered as a batch of one when the tracker finishes")
    func oneEvent() async throws {
        let recorder = InMemoryDestination()
        let tracker = Tracker()
        let sut = tracker.records.batch(strategy: .count(2)).deliver(to: recorder)
        let expected = [[7]]

        tracker.track(Tapped(number: 7))
        tracker.finish()
        try await sut.execute()

        #expect(recorder.numbers == expected)
    }

    @Test("A delivery to no destinations reads the records and completes")
    func noDestinations() async throws {
        let tracker = Tracker()
        let sut = tracker.records.batch(strategy: .count(1)).deliver()

        tracker.track(Tapped(number: 1))
        tracker.finish()
        try await sut.execute()
    }

    @Test("Nothing is delivered until the work is executed")
    func lazy() async throws {
        let recorder = InMemoryDestination()
        let tracker = Tracker()
        let sut = tracker.records.batch(strategy: .count(1)).deliver(to: recorder)
        let expectedBefore: [[Int]] = []
        let expected = [[1]]
        tracker.track(Tapped(number: 1))
        tracker.finish()

        let actualBefore = recorder.numbers
        try await sut.execute()

        #expect(actualBefore == expectedBefore)
        #expect(recorder.numbers == expected)
    }

    @Test("Executing a delivery again after its sequence ended completes without delivering again")
    func executeAgain() async throws {
        let recorder = InMemoryDestination()
        let tracker = Tracker()
        let sut = tracker.records.batch(strategy: .count(5)).deliver(to: recorder)
        let expected = [[1]]
        tracker.track(Tapped(number: 1))
        tracker.finish()
        try await sut.execute()

        try await sut.execute()

        #expect(recorder.numbers == expected)
    }

    @Test("Cancelling the delivery delivers none of the pending records")
    func cancelDropsPending() async throws {
        let started = SingleValueSubject<Void>()
        let recorder = InMemoryDestination()
        let tracker = Tracker()
        let sut = tracker.records.batch(strategy: .either(.count(2), StartGate(started: started))).deliver(to: recorder)
        let expected: [[Int]] = []
        tracker.track(Tapped(number: 1))
        let running = Task { try await sut.execute() }
        try await started.execute()

        running.cancel()
        _ = await running.result
        tracker.finish()

        #expect(recorder.numbers == expected)
    }

    @Test("A cancelled delivery throws CancellationError when executed again, and a new one delivers")
    func executeAfterCancel() async throws {
        let started = SingleValueSubject<Void>()
        let recorder = InMemoryDestination()
        let tracker = Tracker()
        let sut = tracker.records.batch(strategy: .either(.count(5), StartGate(started: started))).deliver(to: recorder)
        let expected = [[1]]
        let running = Task { try await sut.execute() }
        try await started.execute()
        running.cancel()
        _ = await running.result
        tracker.track(Tapped(number: 1))
        tracker.finish()

        await #expect(throws: CancellationError.self) {
            try await sut.execute()
        }
        try await tracker.records.batch(strategy: .count(5)).deliver(to: recorder).execute()

        #expect(recorder.numbers == expected)
    }

    @Test("A destination that never returns doesn't hold up delivery to the others")
    func stuckDestination() async throws {
        let stuck = Stuck()
        let recorder = InMemoryDestination()
        let tracker = Tracker()
        let sut = tracker.records.batch(strategy: .count(1)).deliver(to: stuck, recorder)
        let expected = [[1], [2]]
        let running = Task { try await sut.execute() }

        tracker.track(Tapped(number: 1))
        tracker.track(Tapped(number: 2))
        var deliveries = recorder.deliveries.makeAsyncIterator()
        _ = await deliveries.next()
        _ = await deliveries.next()
        let actual = recorder.numbers
        try stuck.gate.send()
        tracker.finish()
        try await running.value

        #expect(actual == expected)
    }

    @Test("A destination that falls behind keeps the newest batches up to the buffer limit, dropping the oldest")
    func dropsOldestBatch() async throws {
        let stuck = Stuck()
        let recorder = InMemoryDestination()
        let tracker = Tracker()
        let sut = tracker.records.batch(strategy: .count(1)).deliver(to: stuck, recorder, batchBufferLimit: 1)
        let expected = [[1], [4]]
        let running = Task { try await sut.execute() }
        tracker.track(Tapped(number: 1))
        try await stuck.entered.execute()

        tracker.track(Tapped(number: 2))
        tracker.track(Tapped(number: 3))
        tracker.track(Tapped(number: 4))
        // The other destination has a buffer of one too, so it may skip batches; once it has the
        // last one, every batch has been handed to the stuck destination's buffer, which is
        // handed each batch first.
        var deliveries = recorder.deliveries.makeAsyncIterator()
        while let batch = await deliveries.next(), (batch.last?.event as? Tapped)?.number != 4 {}
        try stuck.gate.send()
        tracker.finish()
        try await running.value

        #expect(stuck.batches.withLock { $0 } == expected)
    }

    @Test("By default a destination that falls behind keeps its 100 newest waiting batches")
    func defaultBufferLimit() async throws {
        let stuck = Stuck()
        let recorder = InMemoryDestination()
        let tracker = Tracker()
        let sut = tracker.records.batch(strategy: .count(1)).deliver(to: stuck, recorder)
        let expected = [[1]] + (3 ... 102).map { [$0] }
        let running = Task { try await sut.execute() }
        tracker.track(Tapped(number: 1))
        try await stuck.entered.execute()

        for number in 2 ... 102 {
            tracker.track(Tapped(number: number))
        }
        // As in dropsOldestBatch: once the other destination has the last batch, every batch has
        // been handed to the stuck destination's buffer.
        var deliveries = recorder.deliveries.makeAsyncIterator()
        while let batch = await deliveries.next(), (batch.last?.event as? Tapped)?.number != 102 {}
        try stuck.gate.send()
        tracker.finish()
        try await running.value

        #expect(stuck.batches.withLock { $0 } == expected)
    }

    @Test("A strategy's error ends the delivery with that error")
    func strategyError() async {
        let tracker = Tracker()
        let sut = tracker.records.batch(strategy: FailingStrategy<EventRecord>()).deliver(to: InMemoryDestination())

        await #expect(throws: FailingStrategy<EventRecord>.Broken()) {
            try await sut.execute()
        }
    }
}

extension InMemoryDestination {
    /// The numbers of the `Tapped` events received, batch by batch.
    fileprivate var numbers: [[Int]] {
        batches.map { $0.compactMap { ($0.event as? DeliverTests.Tapped)?.number } }
    }
}
