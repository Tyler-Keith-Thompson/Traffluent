// The app lifecycle example of the "Automatic Tracking" article
// (Sources/Traffluent/Traffluent.docc/AutomaticTracking.md), verbatim, so the article cannot drift
// from the code. Its screen views and control activations examples need UIKit, so they run in the
// simulator, in AutomaticScreenTrackingTests and AutomaticControlTrackingUITests.

import EventMacros
import Foundation
import SystemPackage
import Testing
import Traffluent

@Suite("Automatic tracking examples", .timeLimit(.minutes(1)))
struct AutomaticTrackingExamplesTests {
    @Event
    struct SignedUp {
        var plan: String
    }

    @Test("App lifecycle")
    func appLifecycle() async throws {
        // The article's store uses the default directory; this one uses a scratch directory so the
        // test leaves nothing behind.
        let directory = FilePath(NSTemporaryDirectory()).appending("AutomaticTrackingExamplesTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let store = try SegmentStore(directory: directory)  // every @Event, and the lifecycle's own events
        let tracker = Tracker(store: store)
        // In the application delegate's application(_:didFinishLaunchingWithOptions:), kept beside the tracker:
        let lifecycle = tracker.trackLifecycle(
            kinds: [.installed, .updated, .opened, .backgrounded],
            versionStore: FileVersionStore(directory: store.directory)
        )
        let delivery = tracker.records
            .batch(strategy: .either(.count(20), .time(interval: .seconds(30), clock: ContinuousClock()), .lifecycle))
            .deliver(to: ConsoleDestination())
        await lifecycle.finish()
        await tracker.finish()
        try await delivery.execute()  // prints: ApplicationOpened ApplicationOpened(fromBackground: false)
    }
}
