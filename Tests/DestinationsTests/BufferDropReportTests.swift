import Afluent
import Destinations
import Events
import Foundation
import Testing

@Suite("BufferDropReport: merging while unread", .timeLimit(.minutes(1)))
struct BufferDropReportTests {
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

    @Test("Two reports merged add their record and stored record counts and span both reports' times")
    func merged() {
        let sut = BufferDropReport(destinationIndex: 1, recordCount: 3, timestamps: Date(timeIntervalSince1970: 2) ... Date(timeIntervalSince1970: 4), storedRecordCount: 1)
        let later = BufferDropReport(destinationIndex: 1, recordCount: 2, timestamps: Date(timeIntervalSince1970: 1) ... Date(timeIntervalSince1970: 5), storedRecordCount: 2)
        let expected = BufferDropReport(destinationIndex: 1, recordCount: 5, timestamps: Date(timeIntervalSince1970: 1) ... Date(timeIntervalSince1970: 5), storedRecordCount: 3)

        let actual = sut.merged(with: later)

        #expect(actual == expected)
    }

    @Test("A report merged onto counts of Int.max keeps both counts at Int.max")
    func mergedAtMax() {
        let time = Date(timeIntervalSince1970: 1)
        let sut = BufferDropReport(destinationIndex: 0, recordCount: Int.max, timestamps: time ... time, storedRecordCount: Int.max)
        let later = BufferDropReport(destinationIndex: 0, recordCount: 1, timestamps: time ... time, storedRecordCount: 1)
        let expected = BufferDropReport(destinationIndex: 0, recordCount: Int.max, timestamps: time ... time, storedRecordCount: Int.max)

        let actual = sut.merged(with: later)

        #expect(actual == expected)
    }

    @Test("Merged counts are the sum up to Int.max, and Int.max past it")
    func mergedBoundary() {
        let time = Date(timeIntervalSince1970: 1)
        let sut = BufferDropReport(destinationIndex: 0, recordCount: Int.max - 2, timestamps: time ... time, storedRecordCount: Int.max - 2)
        let one = BufferDropReport(destinationIndex: 0, recordCount: 1, timestamps: time ... time, storedRecordCount: 1)
        let three = BufferDropReport(destinationIndex: 0, recordCount: 3, timestamps: time ... time, storedRecordCount: 3)
        let expectedBelow = BufferDropReport(destinationIndex: 0, recordCount: Int.max - 1, timestamps: time ... time, storedRecordCount: Int.max - 1)
        let expectedSaturated = BufferDropReport(destinationIndex: 0, recordCount: Int.max, timestamps: time ... time, storedRecordCount: Int.max)

        let actualBelow = sut.merged(with: one)
        let actualSaturated = sut.merged(with: three)

        #expect(actualBelow == expectedBelow)
        #expect(actualSaturated == expectedSaturated)
    }

    @Test("Drops no one reads wait as one report per destination, counting every dropped batch")
    func onePerDestination() async throws {
        let start = Date(timeIntervalSince1970: 1_000)
        func record(_ number: Int) -> EventRecord {
            EventRecord(event: Tapped(number: number), timestamp: start + TimeInterval(number), sourceLocation: nil)
        }
        let first = Stuck()
        let second = Stuck()
        let recorder = InMemoryDestination()
        let (batches, input) = AsyncStream.makeStream(of: [EventRecord].self)
        var sut: Delivery? = try batches.deliver(to: first, second, recorder, batchBufferLimit: 1)
        let reports = try #require(sut?.bufferDropReports)
        // Batch 1 is held by both, 6 waits in both buffers, and 2 to 5 are dropped from each.
        let expected = [
            BufferDropReport(destinationIndex: 0, recordCount: 4, timestamps: start + 2 ... start + 5, storedRecordCount: 0),
            BufferDropReport(destinationIndex: 1, recordCount: 4, timestamps: start + 2 ... start + 5, storedRecordCount: 0),
        ]
        let running = Task { [sut] in try await sut?.execute() }
        input.yield([record(1)])
        try await first.entered.execute()
        try await second.entered.execute()
        // One at a time, each once the recorder has the one before, so the recorder never falls
        // behind, and every batch reaches the held destinations' buffers before either is let go.
        var deliveries = recorder.deliveries.makeAsyncIterator()
        _ = await deliveries.next()
        for number in 2 ... 6 {
            input.yield([record(number)])
            _ = await deliveries.next()
        }
        try first.gate.send()
        try second.gate.send()
        input.finish()
        try await running.value
        sut = nil

        var actual: [BufferDropReport] = []
        for await report in reports {
            actual.append(report)
        }
        #expect(actual == expected)
    }
}
