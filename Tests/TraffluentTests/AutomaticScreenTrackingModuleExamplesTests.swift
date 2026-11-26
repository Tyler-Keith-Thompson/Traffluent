// The window example of AutomaticScreenTracking's landing article
// (Sources/AutomaticScreenTracking/AutomaticScreenTracking.docc/AutomaticScreenTracking.md),
// verbatim, so the article cannot drift from the code. Its window scene example needs UIKit and runs
// in the simulator, in AutomaticScreenTrackingTests.
#if os(macOS)
import AppKit
import SwiftUI
import Testing
import Traffluent

@MainActor
@Suite("AutomaticScreenTracking module examples: AppKit", .serialized, .timeLimit(.minutes(1)))
struct AutomaticScreenTrackingModuleAppKitExamplesTests {
    struct PreferencesView: View {
        var body: some View {
            Text("Preferences")
        }
    }

    final class PreferencesWindowController: NSWindowController, TrackerProviding {
        let tracker: Tracker

        init(tracker: Tracker) {
            self.tracker = tracker
            super.init(window: NSWindow(contentViewController: NSHostingController(rootView: PreferencesView())))
        }

        required init?(coder: NSCoder) { nil }
    }

    @Test("Window")
    func windowExample() async throws {
        let tracker = Tracker()
        var records = tracker.records.makeAsyncIterator()

        let controller = PreferencesWindowController(tracker: tracker)
        controller.window?.trackScreensAutomatically()  // tracks ScreenViewed(screen: "PreferencesView")
        controller.showWindow(nil)
        defer {
            controller.window?.stopTrackingScreensAutomatically()
            controller.window?.isReleasedWhenClosed = false
            controller.close()
        }
        let actual = try #require(await records.next()?.event as? ScreenViewed)

        #expect(actual == ScreenViewed(screen: "PreferencesView"))
    }
}
#endif
