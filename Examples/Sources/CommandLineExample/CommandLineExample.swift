import Destinations
import ExampleEvents
import Pipelines

/// The Linux and Wasm example: the composition root builds the pipeline, then tracks the launch.
@main
struct CommandLineExample {
    @MainActor
    static func main() async {
        let pipeline = Pipeline(ConsoleDestination())
        await pipeline.track(AppLaunched(platform: .current))
    }
}
