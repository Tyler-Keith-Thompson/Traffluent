import Destinations
import ExampleEvents
import ExampleViews
import Pipelines
import SwiftUI
import Trackers

/// The Apple example app, one source for every Apple platform: the composition root builds the
/// pipeline, runs it for the life of the app, tracks the launch, and hands a tracker to the screen.
/// SwiftUI runs the screen's button actions on tasks of its own, which a `withTracker` binding
/// doesn't reach, so the app passes the tracker down instead.
@main
struct ExampleApp: App {
    private let pipeline = Pipeline(ConsoleDestination())

    init() {
        let pipeline = pipeline
        // Runs for the life of the app. The default strategy never throws and nothing cancels the
        // run, so there is no error to handle.
        Task { try? await pipeline.run().execute() }
        pipeline.track(AppLaunched(platform: .current))
    }

    var body: some Scene {
        WindowGroup {
            ExampleView(tracker: Tracker(pipeline))
        }
    }
}
