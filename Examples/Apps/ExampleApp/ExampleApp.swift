import Destinations
import ExampleEvents
import ExampleViews
import SwiftUI
import Trackers

/// The Apple example app, one source for every Apple platform: the composition root builds the
/// tracker, delivers its records for the life of the app, tracks the launch, and hands the tracker
/// to the screen. SwiftUI runs the screen's button actions on tasks of its own, which a
/// `withTracker` binding doesn't reach, so the app passes the tracker down instead.
@main
struct ExampleApp: App {
    private let tracker = Tracker()

    init() {
        let delivery = tracker.records.batch().deliver(to: ConsoleDestination())
        // Runs for the life of the app. The default batching never throws and nothing cancels
        // the delivery, so there is no error to handle.
        Task { try? await delivery.execute() }
        tracker.track(AppLaunched(platform: .current))
    }

    var body: some Scene {
        WindowGroup {
            ExampleView(tracker: tracker)
        }
    }
}
