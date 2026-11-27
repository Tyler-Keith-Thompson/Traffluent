import AsyncQueues
import PropertyBased
import Testing
import TraffluentTestSupport

@Suite("AsyncQueue: properties", .timeLimit(.minutes(1)))
struct AsyncQueuePropertyTests {
    @Test("Any run of enqueues and reads, with or without a bound, reads what an array keeping the newest elements would", .tags(.randomized))
    func matchesNewestModel() async {
        await propertyCheck(count: 200, input: Gen.bool.array(of: 0 ... 60), Gen.int(in: 0 ... 5)) { operations, bound in
            // A bound of 0 stands for none.
            let limit: Int? = bound == 0 ? nil : bound
            let expected = modelReads(operations, limit: limit)
            let sut = AsyncQueue<Int>(name: "numbers", buffering: limit.map { .newest($0) } ?? .unbounded)
            var iterator = sut.makeAsyncIterator()
            var waiting = 0
            var next = 0
            var actual: [Int] = []

            for enqueues in operations {
                if enqueues {
                    sut.enqueue(next)
                    next += 1
                    waiting = min(waiting + 1, limit ?? .max)
                } else if waiting > 0 {
                    // Only while an element waits, so the read never suspends.
                    if let number = await iterator.next() { actual.append(number) }
                    waiting -= 1
                }
            }
            sut.finish()
            while let number = await iterator.next() {
                actual.append(number)
            }

            #expect(actual == expected)
        }
    }
}

/// The elements a single reader reads, by the definition: each enqueue appends, past the limit
/// dropping the oldest; each read takes the oldest, when one waits; the rest are read at the end.
private func modelReads(_ operations: [Bool], limit: Int?) -> [Int] {
    var waiting: [Int] = []
    var reads: [Int] = []
    var next = 0
    for enqueues in operations {
        if enqueues {
            waiting.append(next)
            next += 1
            if let limit, waiting.count > limit {
                waiting.removeFirst()
            }
        } else if !waiting.isEmpty {
            reads.append(waiting.removeFirst())
        }
    }
    return reads + waiting
}
