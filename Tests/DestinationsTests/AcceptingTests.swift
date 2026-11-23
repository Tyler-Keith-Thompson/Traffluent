import DestinationTesting
import Destinations
import Events
import Foundation
import Synchronization
import Testing
import Trackers

@Suite("accepting(_:)", .timeLimit(.minutes(1)))
struct AcceptingTests {
    struct Viewed: Event {
        var number: Int
    }

    struct AdClicked: Event {
        static let consentCategory = ConsentCategory.advertising
        var number: Int
    }

    struct ChatOpened: Event {
        static let consentCategory = ConsentCategory.functional
        var number: Int
    }

    /// A store as a delivery sees it: records every acknowledgement it is sent.
    final class Acknowledgements: Acknowledger {
        let acknowledged = Mutex<[[UInt64]]>([])

        func willDeliver(_ positions: [UInt64]) -> Set<UInt64> {
            []
        }

        func acknowledge(_ positions: [UInt64]) {
            acknowledged.withLock { $0.append(positions) }
        }
    }

    @Test("A destination that declares no categories receives every category")
    func undeclaredReceivesEverything() async throws {
        let sut = InMemoryDestination()
        let tracker = Tracker()
        let expected = [1, 2, 3]

        tracker.track(Viewed(number: 1))
        tracker.track(AdClicked(number: 2))
        tracker.track(ChatOpened(number: 3))
        await tracker.finish()
        try await tracker.records.batch(strategy: .count(10)).deliver(to: sut).execute()

        #expect(sut.numbers == [expected])
    }

    @Test("A destination accepting categories receives only events of those, in the order tracked")
    func acceptsOnlyItsCategories() async throws {
        let recorder = InMemoryDestination()
        let tracker = Tracker()
        let sut = recorder.accepting(.advertising, .functional)
        let expected = [[2, 3, 5]]

        tracker.track(Viewed(number: 1))
        tracker.track(AdClicked(number: 2))
        tracker.track(ChatOpened(number: 3))
        tracker.track(Viewed(number: 4))
        tracker.track(AdClicked(number: 5))
        await tracker.finish()
        try await tracker.records.batch(strategy: .count(10)).deliver(to: sut).execute()

        #expect(recorder.numbers == expected)
    }

    @Test("Each destination receives its own categories from the same delivery")
    func perDestination() async throws {
        let everything = InMemoryDestination()
        let ads = InMemoryDestination()
        let tracker = Tracker()
        let expectedEverything = [[1, 2]]
        let expectedAds = [[2]]

        tracker.track(Viewed(number: 1))
        tracker.track(AdClicked(number: 2))
        await tracker.finish()
        try await tracker.records.batch(strategy: .count(10)).deliver(to: everything, ads.accepting(.advertising)).execute()

        #expect(everything.numbers == expectedEverything)
        #expect(ads.numbers == expectedAds)
    }

    @Test("A batch with no accepted record isn't handed to the destination, rather than an empty one")
    func noEmptyBatch() async throws {
        let recorder = InMemoryDestination()
        let tracker = Tracker()
        let sut = recorder.accepting(.advertising)
        let expected = [[2]]

        tracker.track(Viewed(number: 1))
        tracker.track(AdClicked(number: 2))
        await tracker.finish()
        try await tracker.records.batch(strategy: .count(1)).deliver(to: sut).execute()

        #expect(recorder.numbers == expected)
    }

    @Test("Accepting twice receives only the categories both accept")
    func nested() async throws {
        let recorder = InMemoryDestination()
        let tracker = Tracker()
        let sut = recorder.accepting(.advertising, .functional).accepting(.functional, .analytics)
        let expected = [[3]]

        tracker.track(Viewed(number: 1))
        tracker.track(AdClicked(number: 2))
        tracker.track(ChatOpened(number: 3))
        await tracker.finish()
        try await tracker.records.batch(strategy: .count(10)).deliver(to: sut).execute()

        #expect(recorder.numbers == expected)
    }

    @Test("A destination accepting no categories receives nothing")
    func acceptsNothing() async throws {
        let recorder = InMemoryDestination()
        let tracker = Tracker()
        let sut = recorder.accepting()
        let expected: [[Int]] = []

        tracker.track(Viewed(number: 1))
        tracker.track(AdClicked(number: 2))
        await tracker.finish()
        try await tracker.records.batch(strategy: .count(10)).deliver(to: sut).execute()

        #expect(recorder.numbers == expected)
    }

    @Test("A batch the destination accepts none of still counts as received, so its store forgets it")
    func filteredBatchAcknowledged() async throws {
        let store = Acknowledgements()
        let recorder = InMemoryDestination()
        let sut = recorder.accepting(.advertising)
        let (batches, input) = AsyncStream.makeStream(of: [EventRecord].self)
        let record = EventRecord(
            event: Viewed(number: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil,
            deliveryTag: DeliveryTag(acknowledger: store, position: 7))
        let expected: [[UInt64]] = [[7]]

        input.yield([record])
        input.finish()
        try await batches.deliver(to: sut).execute()

        #expect(recorder.batches.isEmpty)
        #expect(store.acknowledged.withLock { $0 } == expected)
    }
}

extension InMemoryDestination {
    /// The numbers of the events received, batch by batch.
    fileprivate var numbers: [[Int]] {
        batches.map { batch in
            batch.compactMap { record in
                switch record.event {
                case let event as AcceptingTests.Viewed: event.number
                case let event as AcceptingTests.AdClicked: event.number
                case let event as AcceptingTests.ChatOpened: event.number
                default: nil
                }
            }
        }
    }
}
