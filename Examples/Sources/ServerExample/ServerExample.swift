import Destinations
import ExampleServer
import Hummingbird
import Trackers
import Tracing

/// The server example: the composition root builds the server's own tracker, binds it to the
/// server's task so every request handler reads it as `Tracker.current`, and serves the example
/// routes on 127.0.0.1:8080 until interrupted, among them the collector endpoint the store app
/// delivers to. The batches route records its spans with the bootstrapped
/// `InstrumentationSystem.tracer`; bootstrap a tracer here to export them. The delivery of the
/// server's own events runs beside the server; once the server stops, the tracker is finished,
/// so the delivery sends what is pending and completes.
@main
struct ServerExample {
    @MainActor
    static func main() async throws {
        let tracker = Tracker()
        let delivery = tracker.records.batch().deliver(to: ConsoleDestination())
        let application = Application(
            router: buildRouter(tracer: InstrumentationSystem.tracer),
            configuration: .init(address: .hostname("127.0.0.1", port: 8080))
        )
        try await withTracker(tracker) {
            try await withThrowingTaskGroup { group in
                group.addTask { try await delivery.execute() }
                // Finished whether the service returns or throws; a defer can't await.
                do {
                    try await application.runService()
                } catch {
                    await tracker.finish()
                    throw error
                }
                await tracker.finish()
            }
        }
    }
}
