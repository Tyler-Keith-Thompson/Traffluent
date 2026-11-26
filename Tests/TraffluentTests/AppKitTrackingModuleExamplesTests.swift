// The example of AppKitTracking's landing article
// (Sources/AppKitTracking/AppKitTracking.docc/AppKitTracking.md), verbatim, so the article cannot
// drift from the code. It runs on the Mac; elsewhere AppKitTracking is empty and this file builds
// nothing.
#if os(macOS)
import AppKit
import Testing
import Traffluent

@MainActor
@Suite("AppKitTracking module examples", .serialized, .timeLimit(.minutes(1)))
struct AppKitTrackingModuleExamplesTests {
    @Event
    struct ShareTapped {}

    @Event
    struct CheckoutStarted {
        var cartSize: Int
    }

    final class CartViewController: NSViewController, TrackerProviding {
        let tracker: Tracker

        init(tracker: Tracker) {
            self.tracker = tracker
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) { nil }

        override func loadView() {
            let share = NSButton(title: "Share", target: self, action: #selector(share(_:)))
            share.track(ShareTapped())  // after setting the target and action
            let checkOut = NSButton(title: "Check out", target: self, action: #selector(checkOut(_:)))
            view = NSStackView(views: [share, checkOut])
        }

        @objc func share(_ sender: NSButton) {}

        @objc func checkOut(_ sender: NSButton) {
            sender.tracker.track(CheckoutStarted(cartSize: 3))  // through this controller's tracker
        }
    }

    @Test("Overview")
    func overview() async throws {
        let tracker = Tracker()
        let controller = CartViewController(tracker: tracker)
        let window = NSWindow(contentViewController: controller)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let stack = try #require(controller.view as? NSStackView)
        for button in stack.arrangedSubviews.compactMap({ $0 as? NSButton }) {
            button.performClick(nil)
        }
        await tracker.finish()
        var actual: [String] = []
        for await record in tracker.records {
            actual.append(type(of: record.event).name)
        }
        let expected = ["ShareTapped", "CheckoutStarted"]

        #expect(actual == expected)
    }
}
#endif
