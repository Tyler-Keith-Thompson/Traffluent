// Property tests against a naive reference: a count strategy's batches are the tracked events
// split into chunks of the count.

import Destinations
import Events
import Pipelines
import PropertyBased
import Synchronization
import TraffluentTestSupport
import Testing

@Suite("Pipeline: properties", .timeLimit(.minutes(1)))
struct PipelinePropertyTests {
    struct Tapped: Event {
        var number: Int
    }

    final class Recorder: Destination {
        let numbers = Mutex<[[Int]]>([])

        func receive(_ batch: [EventRecord]) async {
            numbers.withLock { $0.append(batch.compactMap { ($0.event as? Tapped)?.number }) }
        }
    }

    @Test("Under a count strategy, every destination receives the events in chunks of the count, the last one shorter", .tags(.randomized))
    func countChunks() async {
        await propertyCheck(count: 200, input: Gen.int(in: 1 ... 6), Gen.int(in: 0 ... 30)) { size, total in
            let first = Recorder()
            let second = Recorder()
            let sut = Pipeline(first, second, strategy: .count(size))
            let numbers = Array(0 ..< total)
            let expected = stride(from: 0, to: total, by: size).map { Array(numbers[$0 ..< min($0 + size, total)]) }

            for number in numbers {
                sut.track(Tapped(number: number))
            }
            sut.finish()
            try await sut.run().execute()

            #expect(first.numbers.withLock { $0 } == expected)
            #expect(second.numbers.withLock { $0 } == expected)
        }
    }
}
