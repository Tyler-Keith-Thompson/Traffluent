import Destinations
import ExampleEvents
import ExampleServer
import Hummingbird
import Pipelines
import Trackers

/// The server example: the composition root builds the pipeline, binds a tracker to the server's
/// task so every request handler reads it as `Tracker.current`, and serves the example routes on
/// 127.0.0.1:8080 until interrupted. The pipeline runs beside the server and is finished, which
/// delivers what is pending, once the server stops.
@main
struct ServerExample {
    @MainActor
    static func main() async throws {
        let pipeline = Pipeline(ConsoleDestination())
        let application = Application(
            router: buildRouter(),
            configuration: .init(address: .hostname("127.0.0.1", port: 8080))
        )
        try await withTracker(Tracker(pipeline)) {
            Tracker.current.track(AppLaunched(platform: .current))
            try await withThrowingTaskGroup { group in
                group.addTask { try await pipeline.run().execute() }
                defer { pipeline.finish() }
                try await application.runService()
            }
        }
    }
}
