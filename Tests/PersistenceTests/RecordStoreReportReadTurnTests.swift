// Which reader reaches the stream first decides which path a read takes, so these tests run their
// tasks on the main serial executor (swift-concurrency-extras), which runs every job in the order
// it was enqueued: a second reader that sends its gate and then reads is waiting for its turn
// before the test resumes. It changes a global hook, so the suite runs its tests one at a time.
import Afluent
import ConcurrencyExtras
import Events
import Foundation
import Persistence
import Testing

@MainActor
@Suite("RecordStore: one reader of its drop reports at a time", .serialized, .timeLimit(.minutes(1)))
struct RecordStoreReportReadTurnTests {
    struct Tapped: Event, Codable {
        var number: Int
    }

    struct Scrolled: Event {}

    struct Swiped: Event {}

    struct Pinched: Event {}

    @Test("A second reader of dropReports that starts while the first waits ends once the first's iteration ends and the store is gone; the first gets every report, in order", arguments: StoreKind.all)
    func secondReaderWaitsItsTurn(kind: StoreKind) async throws {
        try await withMainSerialExecutor {
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
            let first = Task {
                var dropped: [DropReport] = []
                for await report in reports {
                    dropped.append(report)
                    if dropped.count == 1 { try? firstHoldsTurn.send() }
                }
                return dropped
            }
            _ = sut?.append(record(Scrolled()))
            try await firstHoldsTurn.execute()
            let second = Task {
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
