import Afluent
import Clocks
import Destinations
import Events
import Foundation
import Instrumentation
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

    /// Yields `record`, then, asked for the next element, sends `askedAgain` and ends once
    /// `release` is sent. A batch asks for the next element only after adding the one before to
    /// what is pending, so `askedAgain` tells a test the record is pending.
    struct OneRecordThenWait: AsyncSequence, Sendable {
        let record: EventRecord
        let askedAgain: SingleValueSubject<Void>
        let release: SingleValueSubject<Void>

        func makeAsyncIterator() -> Iterator {
            Iterator(sequence: self)
        }

        struct Iterator: AsyncIteratorProtocol {
            let sequence: OneRecordThenWait
            var yielded = false

            mutating func next() async throws -> EventRecord? {
                guard yielded else {
                    yielded = true
                    return sequence.record
                }
                try? sequence.askedAgain.send()
                try await sequence.release.execute()
                return nil
            }
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
        let records = Mutex<[EventRecord]>([])

        func receive(_ batch: [EventRecord]) async {
            batches.withLock { $0.append(batch.compactMap { ($0.event as? Tapped)?.number }) }
            records.withLock { $0 += batch }
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
        await tracker.finish()
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
        await tracker.finish()
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
        await tracker.finish()
        try await sut.execute()

        #expect(recorder.numbers == expected)
    }

    @Test("The default batching delivers what is pending once 30 seconds pass on its clock")
    func defaultInterval() async throws {
        let clock = TestClock()
        let recorder = InMemoryDestination()
        let pending = SingleValueSubject<Void>()
        let release = SingleValueSubject<Void>()
        // Not a tracker's records: the batch's interval runs from when the delivery starts, so a
        // record that became pending only after the clock moved would wait for the next interval.
        // This sequence says when the record is pending, which a tracker's records can't.
        let records = OneRecordThenWait(
            record: EventRecord(event: Tapped(number: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil),
            askedAgain: pending,
            release: release
        )
        let sut = records.batch(clock: clock).deliver(to: recorder)
        let expected = [[1]]
        let running = Task { try await sut.execute() }
        try await pending.execute()
        // Polled for the reason timeStrategy gives.
        while (try? await clock.checkSuspension()) != nil {}

        await clock.advance(by: .seconds(30))
        var deliveries = recorder.deliveries.makeAsyncIterator()
        _ = await deliveries.next()
        let actual = recorder.numbers
        try release.send()
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
        await tracker.finish()
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
        await tracker.finish()
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

        await tracker.finish()
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
        await tracker.finish()
        try await sut.execute()

        #expect(recorder.numbers == expected)
    }

    @Test("A delivery to no destinations reads the records and completes")
    func noDestinations() async throws {
        let tracker = Tracker()
        let sut = tracker.records.batch(strategy: .count(1)).deliver()

        tracker.track(Tapped(number: 1))
        await tracker.finish()
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
        await tracker.finish()

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
        await tracker.finish()
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
        await tracker.finish()

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
        await tracker.finish()

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
        await tracker.finish()
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
        await tracker.finish()
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
        await tracker.finish()
        try await running.value

        #expect(stuck.batches.withLock { $0 } == expected)
    }

    @Test("A batch a destination's full buffer drops is reported with the destination, its record count and its timestamps, and its records kept in memory only are lost")
    func dropReported() async throws {
        let start = Date(timeIntervalSince1970: 1_000)
        func record(_ number: Int, at seconds: TimeInterval) -> EventRecord {
            EventRecord(event: Tapped(number: number), timestamp: start + seconds, sourceLocation: nil)
        }
        let recorder = InMemoryDestination()
        let stuck = Stuck()
        let (batches, input) = AsyncStream.makeStream(of: [EventRecord].self)
        let (reports, reporter) = AsyncStream.makeStream(of: BufferDropReport.self)
        let sut = batches.deliver(to: recorder, stuck, batchBufferLimit: 1, bufferDropReporter: reporter)
        let expected = BufferDropReport(destinationIndex: 1, recordCount: 2, timestamps: start + 2 ... start + 3, storedRecordCount: 0)
        let expectedReceived = [[1], [4]]
        let running = Task { try await sut.execute() }
        var deliveries = recorder.deliveries.makeAsyncIterator()
        input.yield([record(1, at: 1)])
        _ = await deliveries.next()
        try await stuck.entered.execute()
        // Out of order, so the report's range is the earliest to the latest, not first to last.
        input.yield([record(3, at: 3), record(2, at: 2)])
        // The other destination has taken this batch, so it has room for the next and drops none.
        _ = await deliveries.next()
        input.yield([record(4, at: 4)])
        var received = reports.makeAsyncIterator()

        let actual = await received.next()
        try stuck.gate.send()
        input.finish()
        try await running.value
        reporter.finish()
        let actualAfter = await received.next()

        let actualReceived = stuck.batches.withLock { $0 }
        #expect(actual == expected)
        #expect(actualAfter == nil)
        #expect(actualReceived == expectedReceived)
    }

    @Test("A store that can't read its records back never has a dropped batch's records acknowledged, and is still told of the others")
    func storeWithoutReadBack() async throws {
        /// A store that keeps records only by position, and records what it is told.
        final class Ledger: Acknowledger {
            let acknowledged = Mutex<[UInt64]>([])

            func willDeliver(_ positions: [UInt64]) -> Set<UInt64> {
                []
            }

            func acknowledge(_ positions: [UInt64]) {
                acknowledged.withLock { $0 += positions }
            }
        }
        let ledger = Ledger()
        let timestamp = Date(timeIntervalSince1970: 1_000)
        func record(_ number: Int) -> EventRecord {
            EventRecord(event: Tapped(number: number), timestamp: timestamp, sourceLocation: nil, deliveryTag: DeliveryTag(acknowledger: ledger, position: UInt64(number)))
        }
        let stuck = Stuck()
        let (batches, input) = AsyncStream.makeStream(of: [EventRecord].self)
        let (reports, reporter) = AsyncStream.makeStream(of: BufferDropReport.self)
        let sut = batches.deliver(to: stuck, batchBufferLimit: 1, bufferDropReporter: reporter)
        let expectedReport = BufferDropReport(destinationIndex: 0, recordCount: 1, timestamps: timestamp ... timestamp, storedRecordCount: 1)
        let expectedReceived = [[1], [3]]
        let expectedAcknowledged: [UInt64] = [1, 3]
        let running = Task { try await sut.execute() }
        input.yield([record(1)])
        try await stuck.entered.execute()
        input.yield([record(2)])
        input.yield([record(3)])
        var received = reports.makeAsyncIterator()

        let actualReport = await received.next()
        try stuck.gate.send()
        input.finish()
        try await running.value

        let actualReceived = stuck.batches.withLock { $0 }
        let actualAcknowledged = ledger.acknowledged.withLock { $0 }
        #expect(actualReport == expectedReport)
        #expect(actualReceived == expectedReceived)
        #expect(actualAcknowledged == expectedAcknowledged)
    }

    /// A store keeping records in memory by position, which reads them back without their
    /// context, as a store on disk does, and records what it is told.
    @Test("A batch handed over after the delivery was cancelled isn't marked as being delivered")
    func batchAfterCancellation() async throws {
        final class Marks: Acknowledger {
            let marked = Mutex<[UInt64]>([])

            func willDeliver(_ positions: [UInt64]) -> Set<UInt64> {
                marked.withLock { $0 += positions }
                return []
            }

            func acknowledge(_ positions: [UInt64]) {}
        }
        /// Yields `first`, then waits until it is cancelled (sending `waiting` first) and yields
        /// `last`, as a batching sequence hands over what is pending when a cancelled delivery
        /// ends its records.
        struct LastBatchOnCancel: AsyncSequence, Sendable {
            let first: [EventRecord]
            let last: [EventRecord]
            let waiting: SingleValueSubject<Void>

            func makeAsyncIterator() -> Iterator {
                Iterator(sequence: self)
            }

            struct Iterator: AsyncIteratorProtocol {
                let sequence: LastBatchOnCancel
                var step = 0

                mutating func next() async throws -> [EventRecord]? {
                    step += 1
                    switch step {
                    case 1:
                        return sequence.first
                    case 2:
                        let cancelled = SingleValueSubject<Void>()
                        try? sequence.waiting.send()
                        await withTaskCancellationHandler {
                            try? await cancelled.execute()
                        } onCancel: {
                            try? cancelled.send()
                        }
                        return sequence.last
                    default:
                        return nil
                    }
                }
            }
        }
        let marks = Marks()
        let timestamp = Date(timeIntervalSince1970: 1_000)
        func record(_ number: Int) -> EventRecord {
            EventRecord(event: Tapped(number: number), timestamp: timestamp, sourceLocation: nil, deliveryTag: DeliveryTag(acknowledger: marks, position: UInt64(number)))
        }
        let waiting = SingleValueSubject<Void>()
        let sut = LastBatchOnCancel(first: [record(1)], last: [record(2)], waiting: waiting).deliver(to: InMemoryDestination())
        let expectedMarked: [UInt64] = [1]
        let delivery = Task { try await sut.execute() }
        try await waiting.execute()

        delivery.cancel()
        _ = try? await delivery.value

        let actualMarked = marks.marked.withLock { $0 }
        #expect(actualMarked == expectedMarked)
    }

    final class Shelf: Acknowledger {
        let kept = Mutex<[UInt64: EventRecord]>([:])
        let acknowledged = Mutex<[UInt64]>([])

        /// `event`, tracked at `timestamp` in `context`, kept at `position`.
        func record(_ event: Tapped, at position: UInt64, timestamp: Date, context: ServiceContext = .topLevel) -> EventRecord {
            let record = EventRecord(event: event, timestamp: timestamp, sourceLocation: nil, context: context, deliveryTag: DeliveryTag(acknowledger: self, position: position))
            kept.withLock { $0[position] = record }
            return record
        }

        func willDeliver(_ positions: [UInt64]) -> Set<UInt64> {
            []
        }

        func acknowledge(_ positions: [UInt64]) {
            acknowledged.withLock { $0 += positions }
        }

        func records(at positions: [UInt64]) -> [EventRecord] {
            kept.withLock { kept in
                positions.compactMap { kept[$0] }.map { record in
                    var stripped = record
                    stripped.context = .topLevel
                    return stripped
                }
            }
        }
    }

    enum ScreenKey: ServiceContextKey {
        typealias Value = String
    }

    @Test("A record a full buffer dropped is sent again with the context it was tracked in")
    func readBackKeepsContext() async throws {
        let shelf = Shelf()
        let timestamp = Date(timeIntervalSince1970: 1_000)
        var checkout = ServiceContext.topLevel
        checkout[ScreenKey.self] = "Checkout"
        let stuck = Stuck()
        let (batches, input) = AsyncStream.makeStream(of: [EventRecord].self)
        let (reports, reporter) = AsyncStream.makeStream(of: BufferDropReport.self)
        let sut = batches.deliver(to: stuck, batchBufferLimit: 1, bufferDropReporter: reporter)
        let expectedReceived = [[1], [3], [2]]
        let expectedScreen: String? = "Checkout"
        let running = Task { try await sut.execute() }
        var received = reports.makeAsyncIterator()
        input.yield([shelf.record(Tapped(number: 1), at: 1, timestamp: timestamp)])
        try await stuck.entered.execute()
        input.yield([shelf.record(Tapped(number: 2), at: 2, timestamp: timestamp, context: checkout)])
        input.yield([shelf.record(Tapped(number: 3), at: 3, timestamp: timestamp)])
        _ = await received.next()

        try stuck.gate.send()
        input.finish()
        try await running.value

        let actualReceived = stuck.batches.withLock { $0 }
        let actualScreen = stuck.records.withLock { $0.last?.context[ScreenKey.self] }
        #expect(actualReceived == expectedReceived)
        #expect(actualScreen == expectedScreen)
    }

    @Test("A record a store reads back tagged with another store is neither sent nor counted as received")
    func readBackOtherStoreIgnored() async throws {
        /// A store that answers a read with another store's records at the same positions.
        final class Impostor: Acknowledger {
            let other: Shelf
            let acknowledged = Mutex<[UInt64]>([])

            init(other: Shelf) {
                self.other = other
            }

            func willDeliver(_ positions: [UInt64]) -> Set<UInt64> {
                []
            }

            func acknowledge(_ positions: [UInt64]) {
                acknowledged.withLock { $0 += positions }
            }

            func records(at positions: [UInt64]) -> [EventRecord] {
                other.records(at: positions)
            }
        }
        let other = Shelf()
        let impostor = Impostor(other: other)
        let timestamp = Date(timeIntervalSince1970: 1_000)
        func record(_ number: Int) -> EventRecord {
            EventRecord(event: Tapped(number: number), timestamp: timestamp, sourceLocation: nil, deliveryTag: DeliveryTag(acknowledger: impostor, position: UInt64(number)))
        }
        _ = other.record(Tapped(number: 2), at: 2, timestamp: timestamp)
        let stuck = Stuck()
        let (batches, input) = AsyncStream.makeStream(of: [EventRecord].self)
        let (reports, reporter) = AsyncStream.makeStream(of: BufferDropReport.self)
        let sut = batches.deliver(to: stuck, batchBufferLimit: 1, bufferDropReporter: reporter)
        let expectedReceived = [[1], [3]]
        let expectedAcknowledged: [UInt64] = [1, 3]
        let running = Task { try await sut.execute() }
        var received = reports.makeAsyncIterator()
        input.yield([record(1)])
        try await stuck.entered.execute()
        input.yield([record(2)])
        input.yield([record(3)])
        _ = await received.next()

        try stuck.gate.send()
        input.finish()
        try await running.value

        let actualReceived = stuck.batches.withLock { $0 }
        let actualAcknowledged = impostor.acknowledged.withLock { $0 }
        #expect(actualReceived == expectedReceived)
        #expect(actualAcknowledged == expectedAcknowledged)
    }

    @Test("A destination more than ten buffers behind has the oldest of its dropped batches left in the store, unacknowledged, and the rest read back")
    func droppedBatchesBounded() async throws {
        let shelf = Shelf()
        let timestamp = Date(timeIntervalSince1970: 1_000)
        let stuck = Stuck()
        let (batches, input) = AsyncStream.makeStream(of: [EventRecord].self)
        let (reports, reporter) = AsyncStream.makeStream(of: BufferDropReport.self)
        let sut = batches.deliver(to: stuck, batchBufferLimit: 1, bufferDropReporter: reporter)
        // 1 is received, 2 to 12 dropped in turn, 13 waits; 10 dropped batches are kept.
        let dropCount = 11
        let expectedReceived = [[1], [13]] + (3 ... 12).map { [$0] }
        let expectedAcknowledged: [UInt64] = [1] + Array(3 ... 13)
        let running = Task { try await sut.execute() }
        var received = reports.makeAsyncIterator()
        input.yield([shelf.record(Tapped(number: 1), at: 1, timestamp: timestamp)])
        try await stuck.entered.execute()
        for number in 2 ... 13 {
            input.yield([shelf.record(Tapped(number: number), at: UInt64(number), timestamp: timestamp)])
        }
        for _ in 0 ..< dropCount {
            _ = await received.next()
        }

        try stuck.gate.send()
        input.finish()
        try await running.value

        let actualReceived = stuck.batches.withLock { $0 }
        let actualAcknowledged = shelf.acknowledged.withLock { $0 }.sorted()
        #expect(actualReceived == expectedReceived)
        #expect(actualAcknowledged == expectedAcknowledged)
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
