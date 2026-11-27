// Which reader reaches the stream first decides which path a read takes, so these tests run their
// tasks on the main serial executor (swift-concurrency-extras), which runs every job in the order
// it was enqueued: a second reader that sends its gate and then reads is waiting for its turn
// before the test resumes. It changes a global hook, so the suite runs its tests one at a time.
import Afluent
import ConcurrencyExtras
import Destinations
import Events
import Foundation
import Testing

@MainActor
@Suite("InMemoryDestination: one reader of its deliveries at a time", .serialized, .timeLimit(.minutes(1)))
struct InMemoryDestinationReadTurnTests {
    struct Tapped: Event {
        var number: Int
    }

    @Test("A second reader of deliveries that starts while the first waits ends once the first's iteration ends and every copy of the destination is gone; the first gets every batch, in order")
    func secondReaderWaitsItsTurn() async throws {
        try await withMainSerialExecutor {
            var sut: InMemoryDestination? = InMemoryDestination()
            let deliveries = try #require(sut?.deliveries)
            let firstHoldsTurn = SingleValueSubject<Void>()
            let secondAboutToRead = SingleValueSubject<Void>()
            let batches = (0 ..< 3).map { number in
                [EventRecord(event: Tapped(number: number), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)]
            }
            let expectedFirst = batches.map { $0.map(\.id) }
            let expectedSecond: [[UUID]] = []
            let first = Task {
                var received: [[UUID]] = []
                for await batch in deliveries {
                    received.append(batch.map(\.id))
                    if received.count == 1 { try? firstHoldsTurn.send() }
                }
                return received
            }
            await sut?.receive(batches[0])
            try await firstHoldsTurn.execute()
            let second = Task {
                var received: [[UUID]] = []
                try? secondAboutToRead.send()
                for await batch in deliveries {
                    received.append(batch.map(\.id))
                }
                return received
            }
            try await secondAboutToRead.execute()

            await sut?.receive(batches[1])
            await sut?.receive(batches[2])
            sut = nil
            let actualFirst = await first.value
            let actualSecond = await second.value

            #expect(actualFirst == expectedFirst)
            #expect(actualSecond == expectedSecond)
        }
    }

    @Test("The deliveries end once every copy of the destination is gone and every batch kept is read")
    func deliveriesEndWithDestination() async throws {
        try await withMainSerialExecutor {
            var sut: InMemoryDestination? = InMemoryDestination()
            let deliveries = try #require(sut?.deliveries)
            let batch = [EventRecord(event: Tapped(number: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)]
            let expected = [batch.map(\.id)]
            await sut?.receive(batch)

            sut = nil

            var actual: [[UUID]] = []
            for await received in deliveries {
                actual.append(received.map(\.id))
            }
            #expect(actual == expected)
        }
    }
}
