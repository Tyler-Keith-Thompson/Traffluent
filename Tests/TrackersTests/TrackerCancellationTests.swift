// Where a cancellation lands decides which path a read takes, so these tests run their tasks on
// the main serial executor (swift-concurrency-extras), which runs every job in the order it was
// enqueued. It changes a global hook, so the suite runs its tests one at a time.
import Afluent
import ConcurrencyExtras
import DestinationTesting
import Destinations
import Events
import Synchronization
import Testing
import Trackers

extension SerializedSuites {
    @MainActor
    @Suite("Tracker: cancelled reads", .serialized, .timeLimit(.minutes(1)))
    struct TrackerCancellationTests {
        struct Tapped: Event {
            var number: Int
        }

        @Test("A read cancelled while it waits returns nil, and the next read takes over its wait")
        func cancelWhileWaiting() async throws {
            try await withMainSerialExecutor {
                let sut = Tracker()
                let aboutToRead = SingleValueSubject<Void>()
                let expected = [1]
                let reading = Task {
                    var records = sut.records.makeAsyncIterator()
                    try? aboutToRead.send()
                    return await records.next()
                }
                // The reader runs to its wait before the serial executor resumes this test.
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

        @Test("A record that arrives after its reader was cancelled is kept for the next read")
        func recordArrivesWithNoReader() async throws {
            try await withMainSerialExecutor {
                let sut = Tracker()
                let aboutToRead = SingleValueSubject<Void>()
                let expected = [1]
                let reading = Task {
                    var records = sut.records.makeAsyncIterator()
                    try? aboutToRead.send()
                    return await records.next()
                }
                try await aboutToRead.execute()
                reading.cancel()
                _ = await reading.value

                sut.track(Tapped(number: 1))
                // On the serial executor, yielding runs the read the record resumed, which finds
                // no reader waiting.
                await Task.yield()
                await sut.finish()

                var actual: [Int] = []
                for await record in sut.records {
                    actual.append((record.event as? Tapped)?.number ?? -1)
                }
                #expect(actual == expected)
            }
        }

        @Test("A read cancelled before it runs returns nil and takes nothing")
        func cancelBeforeReading() async {
            await withMainSerialExecutor {
                let sut = Tracker()
                let expected = [1]
                sut.track(Tapped(number: 1))
                let reading = Task {
                    var records = sut.records.makeAsyncIterator()
                    return await records.next()
                }

                // The serial executor hasn't run the reader yet.
                reading.cancel()
                let actualCancelled = await reading.value
                await sut.finish()

                var actual: [Int] = []
                for await record in sut.records {
                    actual.append((record.event as? Tapped)?.number ?? -1)
                }
                #expect(actualCancelled == nil)
                #expect(actual == expected)
            }
        }

        @Test("After a delivery is cancelled mid-backlog, the next gets every record the cancelled one didn't read, once")
        func backlogAfterCancelledDelivery() async throws {
            try await withMainSerialExecutor {
                let sut = Tracker()
                let thirdRead = SingleValueSubject<Void>()
                let requests = Mutex(0)
                let readByCancelled = Mutex<[Int]>([])
                let cancelledDestination = InMemoryDestination()
                let next = InMemoryDestination()
                let expected = [1, 2, 3, 4, 5]
                for number in 1 ... 3 {
                    sut.track(Tapped(number: number))
                }
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
                let running = Task { try await cancelled.execute() }
                try await thirdRead.execute()

                running.cancel()
                _ = await running.result
                sut.track(Tapped(number: 4))
                sut.track(Tapped(number: 5))
                await sut.finish()
                try await sut.records.batch(strategy: .count(10)).deliver(to: next).execute()

                let deliveredNext = next.records.compactMap { ($0.event as? Tapped)?.number }
                let actual = readByCancelled.withLock { $0 } + deliveredNext
                #expect(actual == expected)
            }
        }
    }
}
