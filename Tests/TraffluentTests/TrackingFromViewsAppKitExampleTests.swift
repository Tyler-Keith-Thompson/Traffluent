// The AppKit example of the "Tracking from SwiftUI, UIKit and AppKit" article
// (Sources/Traffluent/Traffluent.docc/TrackingFromViews.md), verbatim. It runs on the Mac; elsewhere
// AppKitTracking is empty and this file builds nothing. The UIKit example runs in the simulator, in
// SwiftUITrackingTests.
#if os(macOS)
import AppKit
import Testing
import Traffluent

@MainActor
@Suite("Tracking from views examples: AppKit", .serialized, .timeLimit(.minutes(1)))
struct TrackingFromViewsAppKitExampleTests {
    struct SignedUp: Event {
        var plan: String
    }

    struct ShareTapped: Event {}

    final class CheckoutWindowController: NSWindowController, TrackerProviding {
        let tracker: Tracker

        init(window: NSWindow, tracker: Tracker) {
            self.tracker = tracker
            super.init(window: window)
        }

        required init?(coder: NSCoder) { nil }

        @objc func signUp(_ sender: NSButton) {
            sender.tracker.track(SignedUp(plan: "pro"))
        }
    }

    @Test("AppKit")
    func appKit() async {
        let tracker = Tracker()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let controller = CheckoutWindowController(window: window, tracker: tracker)
        defer { controller.close() }

        let share = NSButton(title: "Share", target: nil, action: nil)
        share.track(ShareTapped())  // through the tracker of the window it is in when it is clicked

        let signUp = NSButton(title: "Sign up", target: controller, action: #selector(CheckoutWindowController.signUp(_:)))
        window.contentView?.addSubview(share)
        window.contentView?.addSubview(signUp)
        share.performClick(nil)
        signUp.performClick(nil)
        await tracker.finish()
        var names: [String] = []
        for await record in tracker.records {
            names.append(type(of: record.event).name)
        }

        #expect(names == ["ShareTapped", "SignedUp"])
    }
}
#endif
