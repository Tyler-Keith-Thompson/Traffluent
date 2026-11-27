// The example of the AsyncQueues module's landing article
// (Sources/AsyncQueues/AsyncQueues.docc/AsyncQueues.md), verbatim, so the article cannot drift
// from the code.

import Foundation
import Logging
import Synchronization
import SystemPackage
import Testing
import Traffluent

@Suite("AsyncQueues module examples", .timeLimit(.minutes(1)))
struct AsyncQueuesModuleExamplesTests {
    @Event(name: "signed_up")
    struct SignedUp {
        var plan: String
    }

    struct Scrolled: Event {}

    /// The messages a logger wrote.
    final class Entries: Sendable {
        let written = Mutex<[String]>([])
    }

    struct RecordingHandler: LogHandler {
        let entries: Entries
        var metadata: Logger.Metadata = [:]
        var logLevel: Logger.Level = .trace

        subscript(metadataKey key: String) -> Logger.Metadata.Value? {
            get { metadata[key] }
            set { metadata[key] = newValue }
        }

        func log(event: LogEvent) {
            entries.written.withLock { $0.append("\(event.message)") }
        }
    }

    @Test("A task reads a store's drop reports; another reader waits its turn and ends once the store is gone")
    func readingDropReports() async throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("AsyncQueuesModuleExamplesTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let entries = Entries()
        let logger = Logger(label: "AsyncQueuesModuleExamplesTests") { _ in RecordingHandler(entries: entries) }
        let expectedReport: [DropReport] = [.notPersisted(event: "Scrolled")]
        let expectedLogged = expectedReport.map { "Dropped: \($0)" }
        let later: AsyncQueue<DropReport>
        do {
            let store = try SegmentStore(events: [SignedUp.self], directory: directory)
            _ = store.append(EventRecord(event: Scrolled(), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil))

            let reports = store.dropReports
            Task {
                for await report in reports {
                    logger.warning("Dropped: \(report)")
                }
            }

            later = reports
        }

        // The store is gone, so both readers end. Whichever reads first gets the report: this one,
        // or the example's task, which logs it before its iteration ends and hands this one the
        // turn.
        var actual: [DropReport] = []
        for await report in later {
            actual.append(report)
        }
        let logged = entries.written.withLock { $0 }

        #expect(actual == expectedReport && logged.isEmpty || actual.isEmpty && logged == expectedLogged)
    }

    @Test("An app's own queue gets each store drop report the task forwards, and ends once the store's reports do")
    func queueOfYourOwn() async throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("AsyncQueuesModuleExamplesTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let expected = ["Not stored: \(DropReport.notPersisted(event: "Scrolled"))"]
        let read: AsyncQueue<String>
        do {
            let store = try SegmentStore(events: [SignedUp.self], directory: directory)
            _ = store.append(EventRecord(event: Scrolled(), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil))

            let drops = AsyncQueue<String>.Continuation(name: "the app's drop reports")
            let storeReports = store.dropReports
            Task {
                for await report in storeReports {
                    drops.enqueue("Not stored: \(report)")
                }
                drops.finish()
            }
            let reads = drops.queue

            read = reads
        }

        // The store is gone, so its reports end, and the task finishes the queue after the one.
        var actual: [String] = []
        for await drop in read {
            actual.append(drop)
        }

        #expect(actual == expected)
    }
}
