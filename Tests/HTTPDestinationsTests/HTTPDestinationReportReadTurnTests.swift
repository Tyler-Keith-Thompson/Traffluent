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
import HTTPDestinations
import HTTPTypes
import Testing

@Suite("HTTPDestination: one reader of its drop reports at a time", .timeLimit(.minutes(1)))
struct HTTPDestinationReportReadTurnTests {
    struct SignedUp: Event {
        var plan: String
    }

    /// Encodes a batch as its records' identifiers, one per line, as plain text.
    struct IdentifiersEncoder: BatchEncoder {
        static let transientStatuses: Set<TransientStatus> = []

        func requests(for batch: [EventRecord]) -> BatchRequests<Never> {
            BatchRequests(requests: [EncodedRequest(body: body(of: batch), recordIDs: batch.map(\.id))], skippedRecords: [])
        }

        func body(of batch: [EventRecord]) -> EncodedBatch {
            EncodedBatch(body: Data(batch.map(\.id.uuidString).joined(separator: "\n").utf8), contentType: "text/plain")
        }
    }

    /// Answers every request with 400 Bad Request, which drops the batch for good.
    struct RejectingTransport: HTTPTransport {
        func send(_ request: HTTPRequest, body: Data) async throws(HTTPTransportError) -> HTTPResponse {
            HTTPResponse(status: .badRequest)
        }
    }

    @Test("A second reader of dropReports that starts while the first waits ends once the first's iteration ends and every copy of the destination is gone; the first gets every report, in order")
    func secondReaderWaitsItsTurn() async throws {
        let executor = QueueExecutor.queue(label: "HTTPDestinationReportReadTurnTests")
        try await withTaskExecutorPreference(executor) {
            let endpoint = try #require(URL(string: "https://collector.example.com/batches"))
            var sut: HTTPDestination<RejectingTransport, IdentifiersEncoder>? = HTTPDestination(endpoint: endpoint, transport: RejectingTransport(), encoder: IdentifiersEncoder())
            let reports = try #require(sut?.dropReports)
            let firstHoldsTurn = SingleValueSubject<Void>()
            let secondAboutToRead = SingleValueSubject<Void>()
            let batches = (0 ..< 3).map { number in
                [EventRecord(event: SignedUp(plan: "\(number)"), timestamp: Date(timeIntervalSince1970: Double(number)), sourceLocation: nil)]
            }
            let expectedFirst = batches.map { HTTPDropReport<Never>.rejected(status: .badRequest, recordIDs: $0.map(\.id)) }
            let expectedSecond: [HTTPDropReport<Never>] = []
            let first = Task(executorPreference: executor) {
                var dropped: [HTTPDropReport<Never>] = []
                for await report in reports {
                    dropped.append(report)
                    if dropped.count == 1 { try? firstHoldsTurn.send() }
                }
                return dropped
            }
            await sut?.receive(batches[0])
            try await firstHoldsTurn.execute()
            let second = Task(executorPreference: executor) {
                var dropped: [HTTPDropReport<Never>] = []
                try? secondAboutToRead.send()
                for await report in reports {
                    dropped.append(report)
                }
                return dropped
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
}
