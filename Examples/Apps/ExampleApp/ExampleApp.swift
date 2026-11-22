import Destinations
import ExampleEvents
import ExampleViews
import Pipelines
import SwiftUI

/// The Apple example app, one source for every Apple platform: the composition root builds the
/// pipeline, tracks the launch, and hands the pipeline to the screen.
@main
struct ExampleApp: App {
    private let pipeline = Pipeline(ConsoleDestination())

    init() {
        let pipeline = pipeline
        let launched = AppLaunched(platform: .current)
        Task { await pipeline.track(launched) }
    }

    var body: some Scene {
        WindowGroup {
            ExampleView(pipeline: pipeline)
        }
    }
}
