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
import Events
import Foundation
import Persistence
import Testing

@Suite("RecordStore: one reader of its drop reports at a time", .timeLimit(.minutes(1)))
struct RecordStoreReportReadTurnTests {
    struct Tapped: Event, Codable {
        var number: Int
    }

    struct Scrolled: Event {}

    struct Swiped: Event {}

    struct Pinched: Event {}

    @Test("A second reader of dropReports that starts while the first waits ends once the first's iteration ends and the store is gone; the first gets every report, in order", arguments: StoreKind.all)
    func secondReaderWaitsItsTurn(kind: StoreKind) async throws {
        let executor = QueueExecutor.queue(label: "RecordStoreReportReadTurnTests")
        try await withTaskExecutorPreference(executor) {
            let path = StoreKind.temporaryPath()
            defer { try? FileManager.default.removeItem(atPath: path) }
            func record(_ event: any Event) -> EventRecord {
                EventRecord(event: event, timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)
            }
            var sut: (any InspectableStore)? = try kind.open(at: path, events: [Tapped.self]).store
            let reports = try #require(sut?.dropReports)
            let firstHoldsTurn = SingleValueSubject<Void>()
            let secondAboutToRead = SingleValueSubject<Void>()
            let expectedFirst: [DropReport] = [
                .notPersisted(event: "Scrolled"),
                .notPersisted(event: "Swiped"),
                .notPersisted(event: "Pinched"),
            ]
            let expectedSecond: [DropReport] = []
            let first = Task(executorPreference: executor) {
                var dropped: [DropReport] = []
                for await report in reports {
                    dropped.append(report)
                    if dropped.count == 1 { try? firstHoldsTurn.send() }
                }
                return dropped
            }
            _ = sut?.append(record(Scrolled()))
            try await firstHoldsTurn.execute()
            let second = Task(executorPreference: executor) {
                var dropped: [DropReport] = []
                try? secondAboutToRead.send()
                for await report in reports {
                    dropped.append(report)
                }
                return dropped
            }
            try await secondAboutToRead.execute()

            _ = sut?.append(record(Swiped()))
            _ = sut?.append(record(Pinched()))
            sut = nil
            let actualFirst = await first.value
            let actualSecond = await second.value

            #expect(actualFirst == expectedFirst)
            #expect(actualSecond == expectedSecond)
        }
    }
}
