// Which reader reaches the stream first decides which path a read takes, so these tests run their
// tasks on the main serial executor (swift-concurrency-extras), which runs every job in the order
// it was enqueued: a second reader that sends its gate and then reads is waiting for its turn
// before the test resumes. It changes a global hook, so the suite runs its tests one at a time,
// apart from the other SerializedSuites.
import Afluent
import ConcurrencyExtras
import Destinations
import Events
import Foundation
import Testing

extension SerializedSuites {
    @MainActor
    @Suite("Delivery: one reader of its buffer-drop reports at a time", .serialized, .timeLimit(.minutes(1)))
    struct DeliveryReadTurnTests {
        struct Tapped: Event {
            var number: Int
        }

        /// Holds the first batch it receives until `gate` is sent, sending `entered` as it starts to,
        /// so the batches after it fill its buffer.
        final class Stuck: Destination {
            let entered = SingleValueSubject<Void>()
            let gate = SingleValueSubject<Void>()

            func receive(_ batch: [EventRecord]) async {
                guard (try? entered.send()) != nil else { return }
                try? await gate.execute()
            }
        }

        @Test("A second reader of bufferDropReports that starts while the first waits ends once the first's iteration ends and the delivery is gone; the first's reports count every drop")
        func secondReaderWaitsItsTurn() async throws {
            try await withMainSerialExecutor {
                let start = Date(timeIntervalSince1970: 1_000)
                func record(_ number: Int) -> EventRecord {
                    EventRecord(event: Tapped(number: number), timestamp: start + TimeInterval(number), sourceLocation: nil)
                }
                let stuck = Stuck()
                let (batches, input) = AsyncStream.makeStream(of: [EventRecord].self)
                var sut: Delivery? = try batches.deliver(to: stuck, batchBufferLimit: 1)
                let reports = try #require(sut?.bufferDropReports)
                let firstHoldsTurn = SingleValueSubject<Void>()
                let secondAboutToRead = SingleValueSubject<Void>()
                // Batch 1 is received and held, so 2, 3 and 4 are each dropped as the next arrives.
                // Drops no one is waiting for merge, so the first's reports are compared merged.
                let expectedFirst: BufferDropReport? = BufferDropReport(destinationIndex: 0, recordCount: 3, timestamps: start + 2 ... start + 4, storedRecordCount: 0)
                let expectedSecond: [BufferDropReport] = []
                let running = Task { [sut] in try await sut?.execute() }
                let first = Task {
                    var received: [BufferDropReport] = []
                    for await report in reports {
                        received.append(report)
                        if received.count == 1 { try? firstHoldsTurn.send() }
                    }
                    return received
                }
                input.yield([record(1)])
                try await stuck.entered.execute()
                input.yield([record(2)])
                input.yield([record(3)])
                try await firstHoldsTurn.execute()
                let second = Task {
                    var received: [BufferDropReport] = []
                    try? secondAboutToRead.send()
                    for await report in reports {
                        received.append(report)
                    }
                    return received
                }
                try await secondAboutToRead.execute()

                input.yield([record(4)])
                input.yield([record(5)])
                try stuck.gate.send()
                input.finish()
                try await running.value
                sut = nil
                let received = await first.value
                let actualFirst = received.dropFirst().reduce(received.first) { merged, report in merged?.merged(with: report) }
                let actualSecond = await second.value

                #expect(actualFirst == expectedFirst)
                #expect(actualSecond == expectedSecond)
            }
        }

        @Test("A reader of bufferDropReports cancelled while it waits its turn returns nil, and the reports of the reader holding them still count every drop")
        func cancelledWaiterLeavesHolder() async throws {
            try await withMainSerialExecutor {
                let start = Date(timeIntervalSince1970: 1_000)
                func record(_ number: Int) -> EventRecord {
                    EventRecord(event: Tapped(number: number), timestamp: start + TimeInterval(number), sourceLocation: nil)
                }
                let stuck = Stuck()
                let (batches, input) = AsyncStream.makeStream(of: [EventRecord].self)
                var sut: Delivery? = try batches.deliver(to: stuck, batchBufferLimit: 1)
                let reports = try #require(sut?.bufferDropReports)
                let firstHoldsTurn = SingleValueSubject<Void>()
                let secondAboutToRead = SingleValueSubject<Void>()
                let expectedFirst: BufferDropReport? = BufferDropReport(destinationIndex: 0, recordCount: 2, timestamps: start + 2 ... start + 3, storedRecordCount: 0)
                let expectedSecond: BufferDropReport? = nil
                let running = Task { [sut] in try await sut?.execute() }
                let first = Task {
                    var received: [BufferDropReport] = []
                    for await report in reports {
                        received.append(report)
                        if received.count == 1 { try? firstHoldsTurn.send() }
                    }
                    return received
                }
                input.yield([record(1)])
                try await stuck.entered.execute()
                input.yield([record(2)])
                input.yield([record(3)])
                try await firstHoldsTurn.execute()
                let second = Task {
                    var iterator = reports.makeAsyncIterator()
                    try? secondAboutToRead.send()
                    return await iterator.next()
                }
                try await secondAboutToRead.execute()

                second.cancel()
                let actualSecond = await second.value
                input.yield([record(4)])
                try stuck.gate.send()
                input.finish()
                try await running.value
                sut = nil
                let received = await first.value
                let actualFirst = received.dropFirst().reduce(received.first) { merged, report in merged?.merged(with: report) }

                #expect(actualFirst == expectedFirst)
                #expect(actualSecond == expectedSecond)
            }
        }
    }
}
