// The example of the LoggingDestinations module's landing article
// (Sources/LoggingDestinations/LoggingDestinations.docc/LoggingDestinations.md), verbatim, so the
// article cannot drift from the code.

import Logging
import Synchronization
import Testing
import Traffluent

@Suite("LoggingDestinations module examples", .timeLimit(.minutes(1)))
struct LoggingDestinationsModuleExamplesTests {
    struct SignedUp: Event {
        var plan: String
    }

    /// The entries a logger wrote, each as its level, message and `event` metadata.
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
            let description = event.metadata?["event"].map { "\($0)" } ?? ""
            let line = "\(event.level) \(event.message) \(description)"
            entries.written.withLock { $0.append(line) }
        }
    }

    @Test("A logger destination writes each event at the level it is given")
    func loggerDestination() async throws {
        let entries = Entries()
        let logger = Logger(label: "com.example.analytics") { _ in RecordingHandler(entries: entries) }

        let tracker = Tracker()
        let delivery = tracker.records.batch().deliver(
            to: LoggerDestination(logger: logger, level: .debug)
        )
        tracker.track(SignedUp(plan: "pro"))
        await tracker.finish()
        try await delivery.execute()

        let expected = ["debug SignedUp SignedUp(plan: \"pro\")"]
        let actual = entries.written.withLock { $0 }
        #expect(actual == expected)
    }
}
