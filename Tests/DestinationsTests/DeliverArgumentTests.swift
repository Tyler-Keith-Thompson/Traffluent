import Afluent
import Destinations
import Events
import Foundation
import Testing
import Trackers

@Suite("deliver(to:): arguments", .timeLimit(.minutes(1)))
struct DeliverArgumentTests {
    struct Tapped: Event {
        var number: Int
    }

    @Test("A batch buffer limit below 1 throws InvalidBatchBufferLimit", arguments: [0, -1, Int.min])
    func limitBelowOne(_ limit: Int) {
        let tracker = Tracker()

        #expect(throws: InvalidBatchBufferLimit()) {
            _ = try tracker.records.batch(strategy: .count(1)).deliver(to: InMemoryDestination.unbounded(), batchBufferLimit: limit)
        }
    }

    @Test("A batch buffer limit of 1 is accepted, and delivers")
    func limitOfOne() async throws {
        let tracker = Tracker()
        let destination = InMemoryDestination.unbounded()
        let expected = [1]
        tracker.track(Tapped(number: 1))
        await tracker.finish()

        try await tracker.records.batch(strategy: .count(1)).deliver(to: destination, batchBufferLimit: 1).execute()

        let actual = destination.events(of: Tapped.self).map(\.number)
        #expect(actual == expected)
    }
}
