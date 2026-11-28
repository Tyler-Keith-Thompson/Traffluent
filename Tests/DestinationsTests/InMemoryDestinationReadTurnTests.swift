// Which reader reaches the stream first decides which path a read takes, so each test runs itself
// and its tasks on a serial queue of its own (Afluent's QueueExecutor, as their task executor). The
// queue runs one job at a time: a reader's nonisolated call to next() goes on in the job already
// running, rather than being enqueued again, and nothing else on the queue runs until the reader
// suspends in its wait. So a second reader that sends its gate and then reads is waiting for its
// turn before the test resumes. That holds while the suite and the reader closures stay nonisolated
// (@MainActor would win over the task executor) and nothing suspends between a reader's gate and
// its read. The queue is the test's own, not a hook every task in the process goes through, so the
// tests may run alongside any others.
import Afluent
import Destinations
import Events
import Foundation
import Testing

@Suite("InMemoryDestination: one reader of its deliveries at a time", .timeLimit(.minutes(1)))
struct InMemoryDestinationReadTurnTests {
    struct Tapped: Event {
        var number: Int
    }

    @Test("A second reader of deliveries that starts while the first waits ends once the first's iteration ends and every copy of the destination is gone; the first gets every batch, in order")
    func secondReaderWaitsItsTurn() async throws {
        let executor = QueueExecutor.queue(label: "InMemoryDestinationReadTurnTests")
        try await withTaskExecutorPreference(executor) {
            var sut: InMemoryDestination? = InMemoryDestination()
            let deliveries = try #require(sut?.deliveries)
            let firstHoldsTurn = SingleValueSubject<Void>()
            let secondAboutToRead = SingleValueSubject<Void>()
            let batches = (0 ..< 3).map { number in
                [EventRecord(event: Tapped(number: number), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)]
            }
            let expectedFirst = batches.map { $0.map(\.id) }
            let expectedSecond: [[UUID]] = []
            let first = Task(executorPreference: executor) {
                var received: [[UUID]] = []
                for await batch in deliveries {
                    received.append(batch.map(\.id))
                    if received.count == 1 { try? firstHoldsTurn.send() }
                }
                return received
            }
            await sut?.receive(batches[0])
            try await firstHoldsTurn.execute()
            let second = Task(executorPreference: executor) {
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
