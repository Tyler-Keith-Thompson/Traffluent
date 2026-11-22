import Destinations
import ExampleEvents
import Pipelines

/// The Linux and Wasm example: the composition root builds the pipeline, tracks the launch, then
/// finishes and runs the pipeline, which delivers the launch and returns.
@main
struct CommandLineExample {
    @MainActor
    static func main() async throws {
        let pipeline = Pipeline(ConsoleDestination())
        pipeline.track(AppLaunched(platform: .current))
        pipeline.finish()
        try await pipeline.run().execute()
    }
}
