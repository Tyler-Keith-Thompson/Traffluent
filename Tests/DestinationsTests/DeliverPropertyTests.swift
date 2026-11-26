// Property tests against a naive reference: a count strategy's batches are the tracked events
// split into chunks of the count; and, with full buffers dropping batches at random, what each
// destination receives and what a store is told match a model of who has which record.

import Afluent
import Destinations
import Events
import Foundation
import Generators
import Instrumentation
import PropertyBased
import Sampling
import Synchronization
import TraffluentTestSupport
import Testing
import Trackers

@Suite("deliver(to:): properties", .timeLimit(.minutes(1)))
struct DeliverPropertyTests {
    struct Tapped: Event {
        var number: Int
    }

    enum NumberKey: ServiceContextKey {
        typealias Value = Int
    }

    /// A destination whose receives numbered in `blocked` wait until the test opens them, and
    /// which records every record it is handed, as it is handed it.
    final class Valve: Destination {
        let blocked: Set<Int>
        let gates = Mutex<[Int: SingleValueSubject<Void>]>([:])
        let receiveCount = Mutex(0)
        let received = Mutex<[EventRecord]>([])

        init(blocked: Set<Int>) {
            self.blocked = blocked
        }

        func gate(_ index: Int) -> SingleValueSubject<Void> {
            gates.withLock { gates in
                if let gate = gates[index] { return gate }
                let gate = SingleValueSubject<Void>()
                gates[index] = gate
                return gate
            }
        }

        func open(_ index: Int) {
            try? gate(index).send()
        }

        func receive(_ batch: [EventRecord]) async {
            let index = receiveCount.withLock { count in
                defer { count += 1 }
                return count
            }
            received.withLock { $0 += batch }
            if blocked.contains(index) {
                try? await gate(index).execute()
            }
        }
    }

    /// A store keeping records in memory, which reads them back without their context, as a
    /// store on disk does, has lost the records at `lost` by the time they are read back, and
    /// notes any acknowledgement of a record some destination hasn't received.
    final class Shelf: Acknowledger {
        let destinations: [Valve]
        let lost: Set<UInt64>
        let kept = Mutex<[UInt64: EventRecord]>([:])
        let acknowledged = Mutex<[UInt64]>([])
        let early = Mutex<[UInt64]>([])

        init(destinations: [Valve], lost: Set<UInt64>) {
            self.destinations = destinations
            self.lost = lost
        }

        func keep(_ record: EventRecord, at position: UInt64) -> EventRecord {
            var tagged = record
            tagged.deliveryTag = DeliveryTag(acknowledger: self, position: position)
            kept.withLock { [tagged] in $0[position] = tagged }
            return tagged
        }

        func willDeliver(_ positions: [UInt64]) -> Set<UInt64> {
            []
        }

        func acknowledge(_ positions: [UInt64]) {
            let ids = kept.withLock { kept in positions.compactMap { kept[$0]?.id } }
            for (position, id) in zip(positions, ids) where !destinations.allSatisfy({ $0.received.withLock { $0.contains { $0.id == id } } }) {
                early.withLock { $0.append(position) }
            }
            acknowledged.withLock { $0 += positions }
        }

        func records(at positions: [UInt64]) -> [EventRecord] {
            kept.withLock { kept in
                positions.filter { !lost.contains($0) }.compactMap { kept[$0] }.map { record in
                    var stripped = record
                    stripped.context = .topLevel
                    return stripped
                }
            }
        }
    }

    @Test("Under a count strategy, every destination receives the events in chunks of the count, the last one shorter", .tags(.randomized))
    func countChunks() async {
        await propertyCheck(count: 200, input: Gen.int(in: 1 ... 6), Gen.int(in: 0 ... 30)) { size, total in
            let first = InMemoryDestination()
            let second = InMemoryDestination()
            let tracker = Tracker()
            let sut = tracker.records.batch(strategy: .count(size)).deliver(to: first, second)
            let numbers = Array(0 ..< total)
            let expected = stride(from: 0, to: total, by: size).map { Array(numbers[$0 ..< min($0 + size, total)]) }

            for number in numbers {
                tracker.track(Tapped(number: number))
            }
            await tracker.finish()
            try await sut.execute()

            #expect(first.numbers == expected)
            #expect(second.numbers == expected)
        }
    }

    @Test("With two destinations falling behind and catching up at random, each gets each record at most once and every stored one its store still has, in its context, and a store is told of a record only once both have it", .tags(.randomized))
    func dropsAndReadBack() async {
        await propertyCheck(count: 100, input: Gen.uint64(in: .min ... .max)) { seed in
            var random = Xoshiro256StarStar(seed: seed)
            // At most 11 batches, so a destination's buffer drops at most 10 of them, which the
            // delivery keeps track of whatever the limit; past that the oldest is left in the
            // store for the next launch, which droppedBatchesBounded checks.
            let batchCount = random.integer(in: 1 ... 11)
            let limit = random.integer(in: 1 ... 3)
            // A destination receives each batch once, and each dropped one once more at most.
            let receiveBound = 2 * batchCount
            let valves = (0 ..< 2).map { _ in
                Valve(blocked: Set((0 ..< receiveBound).filter { _ in random.bernoulli(0.5) }))
            }
            var stored: [UInt64: Int] = [:]
            var lost: Set<UInt64> = []
            var batches: [[EventRecord]] = []
            var number = 0
            for _ in 0 ..< batchCount {
                var batch: [EventRecord] = []
                for _ in 0 ..< random.integer(in: 1 ... 3) {
                    number += 1
                    var context = ServiceContext.topLevel
                    context[NumberKey.self] = number
                    batch.append(EventRecord(event: Tapped(number: number), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil, context: context))
                    if random.bernoulli(0.8) {
                        stored[UInt64(number)] = number
                        if random.bernoulli(0.2) { lost.insert(UInt64(number)) }
                    }
                }
                batches.append(batch)
            }
            let shelf = Shelf(destinations: valves, lost: lost)
            let tagged = batches.map { batch in
                batch.map { record in
                    let number = (record.event as! Tapped).number
                    return stored[UInt64(number)] == nil ? record : shelf.keep(record, at: UInt64(number))
                }
            }
            let opens = tagged.map { _ in (0 ..< random.integer(in: 0 ... 2)).map { _ in (random.integer(in: 0 ... 1), random.integer(in: 0 ..< receiveBound)) } }
            let (input, continuation) = AsyncStream.makeStream(of: [EventRecord].self)
            let sut = input.deliver(to: valves[0], valves[1], batchBufferLimit: limit)
            let kept = Set(stored.keys).subtracting(lost)

            let running = Task { try await sut.execute() }
            for (batch, batchOpens) in zip(tagged, opens) {
                continuation.yield(batch)
                for (valve, index) in batchOpens {
                    valves[valve].open(index)
                }
            }
            for valve in valves {
                for index in 0 ..< receiveBound { valve.open(index) }
            }
            continuation.finish()
            try await running.value

            let actualEarly = shelf.early.withLock { $0 }
            let actualAcknowledged = shelf.acknowledged.withLock { $0 }
            #expect(actualEarly.isEmpty)
            #expect(Set(actualAcknowledged).count == actualAcknowledged.count)
            #expect(kept.isSubset(of: Set(actualAcknowledged)))
            for valve in valves {
                let actual = valve.received.withLock { $0 }
                let numbers = actual.map { ($0.event as! Tapped).number }
                let receivedPositions = Set(numbers.map(UInt64.init))
                let contextsKept = actual.allSatisfy { $0.context[NumberKey.self] == ($0.event as! Tapped).number }
                #expect(Set(numbers).count == numbers.count)
                #expect(kept.isSubset(of: receivedPositions))
                #expect(contextsKept)
            }
        }
    }
}

extension InMemoryDestination {
    /// The numbers of the `Tapped` events received, batch by batch.
    fileprivate var numbers: [[Int]] {
        batches.map { $0.compactMap { ($0.event as? DeliverPropertyTests.Tapped)?.number } }
    }
}
