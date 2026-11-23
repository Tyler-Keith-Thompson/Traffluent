import Destinations
import ExampleEvents
import Trackers

/// The Linux and Wasm example: the composition root builds the tracker and its delivery, binds
/// the tracker to the program's task, tracks the launch through `Tracker.current`, then finishes
/// the tracker and runs the delivery, which delivers the launch and returns.
@main
struct CommandLineExample {
    @MainActor
    static func main() async throws {
        let tracker = Tracker()
        let delivery = tracker.records.batch().deliver(to: ConsoleDestination())
        withTracker(tracker) {
            Tracker.current.track(AppLaunched(platform: .current))
        }
        await tracker.finish()
        try await delivery.execute()
    }
}
