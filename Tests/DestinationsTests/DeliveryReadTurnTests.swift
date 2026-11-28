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

@Suite("Delivery: one reader of its buffer-drop reports at a time", .timeLimit(.minutes(1)))
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
        let executor = QueueExecutor.queue(label: "DeliveryReadTurnTests")
        try await withTaskExecutorPreference(executor) {
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
            let everyDropReported = SingleValueSubject<Void>()
            // Batch 1 is received and held, so 2, 3 and 4 are each dropped as the next arrives.
            // Drops no one is waiting for merge, so the first's reports are compared merged.
            let expectedFirst: BufferDropReport? = BufferDropReport(destinationIndex: 0, recordCount: 3, timestamps: start + 2 ... start + 4, storedRecordCount: 0)
            let expectedSecond: [BufferDropReport] = []
            // The delivery runs on the global executor, apart from the test's queue, so the test
            // waits for the drops it expects before it lets the held batch go.
            let running = Task { [sut] in try await sut?.execute() }
            let first = Task(executorPreference: executor) {
                var received: [BufferDropReport] = []
                for await report in reports {
                    received.append(report)
                    if received.count == 1 { try? firstHoldsTurn.send() }
                    if received.map(\.recordCount).reduce(0, +) == expectedFirst?.recordCount { try? everyDropReported.send() }
                }
                return received
            }
            input.yield([record(1)])
            try await stuck.entered.execute()
            input.yield([record(2)])
            input.yield([record(3)])
            try await firstHoldsTurn.execute()
            let second = Task(executorPreference: executor) {
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
            try await everyDropReported.execute()
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
        let executor = QueueExecutor.queue(label: "DeliveryReadTurnTests")
        try await withTaskExecutorPreference(executor) {
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
            let everyDropReported = SingleValueSubject<Void>()
            let expectedFirst: BufferDropReport? = BufferDropReport(destinationIndex: 0, recordCount: 2, timestamps: start + 2 ... start + 3, storedRecordCount: 0)
            let expectedSecond: BufferDropReport? = nil
            // The delivery runs on the global executor, apart from the test's queue, so the test
            // waits for the drops it expects before it lets the held batch go.
            let running = Task { [sut] in try await sut?.execute() }
            let first = Task(executorPreference: executor) {
                var received: [BufferDropReport] = []
                for await report in reports {
                    received.append(report)
                    if received.count == 1 { try? firstHoldsTurn.send() }
                    if received.map(\.recordCount).reduce(0, +) == expectedFirst?.recordCount { try? everyDropReported.send() }
                }
                return received
            }
            input.yield([record(1)])
            try await stuck.entered.execute()
            input.yield([record(2)])
            input.yield([record(3)])
            try await firstHoldsTurn.execute()
            let second = Task(executorPreference: executor) {
                var iterator = reports.makeAsyncIterator()
                try? secondAboutToRead.send()
                return await iterator.next()
            }
            try await secondAboutToRead.execute()

            second.cancel()
            let actualSecond = await second.value
            input.yield([record(4)])
            try await everyDropReported.execute()
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
