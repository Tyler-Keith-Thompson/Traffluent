// Property tests against a naive reference: an enriched destination receives the tracked records
// batch by batch, each with the enricher's value for it, while a sibling fed the same batches
// receives them without it.

import Destinations
import Events
import Instrumentation
import PropertyBased
import TraffluentTestSupport
import Testing
import Trackers

@Suite("enriched(by:): properties", .timeLimit(.minutes(1)))
struct EnrichedPropertyTests {
    struct Viewed: Event {
        var number: Int
    }

    enum TimesEnrichedKey: ServiceContextKey {
        typealias Value = Int
    }

    @Test("Under a count strategy, an enriched destination receives every batch with each record enriched once, and a sibling the same batches without it", .tags(.randomized))
    func enrichedBatches() async {
        await propertyCheck(count: 200, input: Gen.int(in: -1_000 ... 1_000).array(of: 0 ... 30), Gen.int(in: 1 ... 5)) { numbers, size in
            let enriched = InMemoryDestination()
            let sibling = InMemoryDestination()
            let tracker = Tracker()
            let counting = Enricher { context in
                // A count rather than a constant, so a record enriched twice, or a context shared
                // between records, would show.
                context[TimesEnrichedKey.self] = (context[TimesEnrichedKey.self] ?? 0) + 1
            }
            let sut = tracker.records.batch(strategy: .count(size)).deliver(to: enriched.enriched(by: counting), sibling)
            let expectedBatches = stride(from: 0, to: numbers.count, by: size)
                .map { Array(numbers[$0 ..< min($0 + size, numbers.count)]) }
            let expectedEnriched = expectedBatches.map { $0.map { _ in 1 as Int? } }
            let expectedSibling = expectedBatches.map { $0.map { _ in nil as Int? } }

            for number in numbers {
                tracker.track(Viewed(number: number))
            }
            await tracker.finish()
            try await sut.execute()

            #expect(enriched.numbers == expectedBatches)
            #expect(sibling.numbers == expectedBatches)
            #expect(enriched.timesEnriched == expectedEnriched)
            #expect(sibling.timesEnriched == expectedSibling)
        }
    }
}

extension InMemoryDestination {
    /// The numbers of the events received, batch by batch.
    fileprivate var numbers: [[Int]] {
        batches.map { batch in
            batch.compactMap { ($0.event as? EnrichedPropertyTests.Viewed)?.number }
        }
    }

    /// How many times each received record was enriched, batch by batch.
    fileprivate var timesEnriched: [[Int?]] {
        batches.map { batch in
            batch.map { $0.context[EnrichedPropertyTests.TimesEnrichedKey.self] }
        }
    }
}
