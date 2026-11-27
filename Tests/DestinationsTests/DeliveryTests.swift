import Destinations
import Events
import Foundation
import Testing
import Trackers

@Suite("Delivery", .timeLimit(.minutes(1)))
struct DeliveryTests {
    struct Tapped: Event, Equatable {
        var number: Int
    }

    @Test("run() starts the delivery without waiting for it")
    func runStarts() async throws {
        let recorder = InMemoryDestination()
        let tracker = Tracker()
        let sut = tracker.records.batch(strategy: .count(1)).deliver(to: recorder)
        let expected = [Tapped(number: 1)]
        var deliveries = recorder.deliveries.makeAsyncIterator()

        sut.run()
        tracker.track(Tapped(number: 1))

        let batch = try #require(await deliveries.next())
        let actual = batch.compactMap { $0.event as? Tapped }
        #expect(actual == expected)
        await tracker.finish()
    }

    @Test("cancel() cancels the delivery for good: executing it then throws CancellationError")
    func cancelSticks() async {
        let tracker = Tracker()
        let sut = tracker.records.batch().deliver(to: InMemoryDestination())

        sut.cancel()

        await #expect(throws: CancellationError.self) {
            try await sut.execute()
        }
        await tracker.finish()
    }
}
