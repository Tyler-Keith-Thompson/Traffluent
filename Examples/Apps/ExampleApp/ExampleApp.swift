import Destinations
import ExampleEvents
import ExampleViews
import Pipelines
import SwiftUI

/// The Apple example app, one source for every Apple platform: the composition root builds the
/// pipeline, runs it for the life of the app, tracks the launch, and hands the pipeline to the
/// screen.
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
            ExampleView(pipeline: pipeline)
        }
    }
}
