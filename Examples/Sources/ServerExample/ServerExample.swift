import Destinations
import ExampleEvents
import ExampleServer
import Hummingbird
import Trackers

/// The server example: the composition root builds the tracker, binds it to the server's task so
/// every request handler reads it as `Tracker.current`, and serves the example routes on
/// 127.0.0.1:8080 until interrupted. The delivery runs beside the server; once the server stops,
/// the tracker is finished, so the delivery sends what is pending and completes.
@main
struct ServerExample {
    @MainActor
    static func main() async throws {
        let tracker = Tracker()
        let delivery = tracker.records.batch().deliver(to: ConsoleDestination())
        let application = Application(
            router: buildRouter(),
            configuration: .init(address: .hostname("127.0.0.1", port: 8080))
        )
        try await withTracker(tracker) {
            Tracker.current.track(AppLaunched(platform: .current))
            try await withThrowingTaskGroup { group in
                group.addTask { try await delivery.execute() }
                defer { tracker.finish() }
                try await application.runService()
            }
        }
    }
}
