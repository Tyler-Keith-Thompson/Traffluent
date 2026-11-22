import Destinations
import ExampleEvents
import ExampleServer
import Hummingbird
import Pipelines

/// The server example: the composition root builds the pipeline and serves the example routes on
/// 127.0.0.1:8080 until interrupted, running the pipeline beside the server and finishing it,
/// which delivers what is pending, once the server stops.
@main
struct ServerExample {
    @MainActor
    static func main() async throws {
        let pipeline = Pipeline(ConsoleDestination())
        pipeline.track(AppLaunched(platform: .current))
        let application = Application(
            router: buildRouter(pipeline: pipeline),
            configuration: .init(address: .hostname("127.0.0.1", port: 8080))
        )
        try await withThrowingTaskGroup { group in
            group.addTask { try await pipeline.run().execute() }
            defer { pipeline.finish() }
            try await application.runService()
        }
    }
}
