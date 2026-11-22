import Destinations
import ExampleEvents
import Pipelines
import Trackers

/// The Linux and Wasm example: the composition root builds the pipeline and binds a tracker to
/// the program's task, tracks the launch through `Tracker.current`, then finishes and runs the
/// pipeline, which delivers the launch and returns.
@main
struct CommandLineExample {
    @MainActor
    static func main() async throws {
        let pipeline = Pipeline(ConsoleDestination())
        withTracker(Tracker(pipeline)) {
            Tracker.current.track(AppLaunched(platform: .current))
        }
        pipeline.finish()
        try await pipeline.run().execute()
    }
}
