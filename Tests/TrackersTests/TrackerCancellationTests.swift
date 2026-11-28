// Where a cancellation lands decides which path a read takes, so a test whose reader must have
// reached a given point when it is cancelled runs itself, the reader and the delivery on a serial
// queue of its own (Afluent's QueueExecutor, as their task executor). The queue runs one job at a
// time: a reader's nonisolated call to next() goes on in the job already running, rather than being
// enqueued again, and nothing else on the queue runs until the reader suspends in its wait. So a
// reader that sends its gate and then reads is waiting where the test expects before the test
// resumes. That holds while the suite and the reader closures stay nonisolated (@MainActor would
// win over the task executor) and nothing suspends between a reader's gate and its read. The queue
// is the test's own, not a hook every task in the process goes through, so the tests may run
// alongside any others.
import Afluent
import Destinations
import Events
import Synchronization
import Testing
import Trackers

@Suite("Tracker: cancelled reads", .timeLimit(.minutes(1)))
struct TrackerCancellationTests {
    struct Tapped: Event {
        var number: Int
    }

    @Test("A read cancelled while it waits returns nil, and the next read takes over its wait")
    func cancelWhileWaiting() async throws {
        let executor = QueueExecutor.queue(label: "TrackerCancellationTests")
        try await withTaskExecutorPreference(executor) {
            let sut = Tracker()
            let aboutToRead = SingleValueSubject<Void>()
            let expected = [1]
            let reading = Task(executorPreference: executor) {
                var records = sut.records.makeAsyncIterator()
                try? aboutToRead.send()
                return await records.next()
            }
            // The reader runs to its wait before the queue resumes this test.
            try await aboutToRead.execute()

            reading.cancel()
            let actualCancelled = await reading.value
            sut.track(Tapped(number: 1))
            await sut.finish()

            var actual: [Int] = []
            for await record in sut.records {
                actual.append((record.event as? Tapped)?.number ?? -1)
            }
            #expect(actualCancelled == nil)
            #expect(actual == expected)
        }
    }

    @Test("A record that arrives after its reader was cancelled, while no iterator exists, is kept for the next read of a tracker still running")
    func recordArrivesWithNoReader() async throws {
        let executor = QueueExecutor.queue(label: "TrackerCancellationTests")
        try await withTaskExecutorPreference(executor) {
            let sut = Tracker()
            let aboutToRead = SingleValueSubject<Void>()
            let expected = 1
            let reading = Task(executorPreference: executor) {
                var records = sut.records.makeAsyncIterator()
                try? aboutToRead.send()
                return await records.next()
            }
            try await aboutToRead.execute()
            reading.cancel()
            _ = await reading.value

            // The record reaches the subscription while the cancelled iterator is gone and no
            // other exists yet.
            sut.track(Tapped(number: 1))
            await sut.flush()
            var records = sut.records.makeAsyncIterator()
            let actual = await records.next().flatMap { ($0.event as? Tapped)?.number }
            await sut.finish()

            #expect(actual == expected)
        }
    }

    @Test("A read cancelled before it runs returns nil and takes nothing")
    func cancelBeforeReading() async {
        let sut = Tracker()
        let expected = [1]
        sut.track(Tapped(number: 1))

        let actualCancelled = await withTaskGroup(of: EventRecord?.self) { group in
            // A task added to a cancelled group starts cancelled, so its read runs cancelled.
            group.cancelAll()
            group.addTask {
                var records = sut.records.makeAsyncIterator()
                return await records.next()
            }
            return await group.next() ?? nil
        }
        await sut.finish()

        var actual: [Int] = []
        for await record in sut.records {
            actual.append((record.event as? Tapped)?.number ?? -1)
        }
        #expect(actualCancelled == nil)
        #expect(actual == expected)
    }

    @Test("After a delivery is cancelled mid-backlog, the next gets every record the cancelled one didn't read, once")
    func backlogAfterCancelledDelivery() async throws {
        let executor = QueueExecutor.queue(label: "TrackerCancellationTests")
        try await withTaskExecutorPreference(executor) {
            let sut = Tracker()
            let thirdRead = SingleValueSubject<Void>()
            let requests = Mutex(0)
            let readByCancelled = Mutex<[Int]>([])
            let cancelledDestination = InMemoryDestination()
            let next = InMemoryDestination()
            let expectedReadByCancelled = [1, 2, 3]
            let expected = [1, 2, 3, 4, 5]
            for number in 1 ... 3 {
                sut.track(Tapped(number: number))
            }
            // The backlog waits in the subscription, so the third read takes its record at once.
            await sut.flush()
            let cancelled = sut.records
                .handleEvents(
                    receiveNext: {
                        let request = requests.withLock {
                            $0 += 1
                            return $0
                        }
                        // Three requests: two records read, the third about to be.
                        if request == 3 { try? thirdRead.send() }
                    },
                    receiveOutput: { record in
                        readByCancelled.withLock { $0.append((record.event as? Tapped)?.number ?? -1) }
                    }
                )
                .batch(strategy: .count(1))
                .deliver(to: cancelledDestination)
            // The delivery's work, and the batch's child tasks under it, run on the queue too, so
            // the third read takes its record before this test resumes and cancels.
            let running = Task(executorPreference: executor) { try await cancelled.work.execute(executorPreference: executor) }
            try await thirdRead.execute()

            running.cancel()
            _ = await running.result
            let actualReadByCancelled = readByCancelled.withLock { $0 }
            sut.track(Tapped(number: 4))
            sut.track(Tapped(number: 5))
            await sut.finish()
            try await sut.records.batch(strategy: .count(10)).deliver(to: next).execute()

            let deliveredNext = next.records.compactMap { ($0.event as? Tapped)?.number }
            let actual = actualReadByCancelled + deliveredNext
            #expect(actualReadByCancelled == expectedReadByCancelled)
            #expect(actual == expected)
        }
    }
}
