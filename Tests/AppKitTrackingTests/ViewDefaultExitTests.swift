// Exit tests, in a file of their own: each runs its body in a child process. AppKit is the Mac's
// alone; elsewhere this target builds empty.
//
// Why child processes: `Tracker.bootstrap` sets the process's default tracker once, and nothing
// can reset it, so every test that bootstraps does it in a child process of its own. Each child
// checks what it sees and exits with a failure when it differs from what is expected.
#if os(macOS)
import AppKit
import AppKitTracking
import Events
import Foundation
import Testing
import Trackers

@Suite("A view below no provider, with a tracker bootstrapped", .timeLimit(.minutes(1)))
struct ViewDefaultExitTests {
    struct ShareTapped: Event, Equatable {}

    struct CheckoutStarted: Event, Equatable {}

    final class NoOpDelegate: NSObject, NSWindowDelegate, TrackerProviding {
        let tracker = Tracker.noOp
    }

    @Test("A view below no provider, and a control's track(_:) there, track through the bootstrapped tracker, looked up as they track")
    func reachesBootstrapped() async {
        await #expect(processExitsWith: .success) {
            let tracker = Tracker()
            let expected = ["CheckoutStarted", "ShareTapped"]

            await MainActor.run {
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                defer { window.close() }
                let button = NSButton(title: "Share", target: nil, action: nil)
                window.contentView?.addSubview(button)
                // Read before the bootstrap: the view's tracker is looked up as it tracks.
                let viewTracker = NSView().tracker
                button.track(ShareTapped())
                do {
                    try Tracker.bootstrap(tracker)
                } catch {
                    exit(EXIT_FAILURE)
                }

                viewTracker.track(CheckoutStarted())
                button.performClick(nil)
            }
            await tracker.finish()

            var actual: [String] = []
            for await record in tracker.records {
                actual.append(type(of: record.event).name)
            }
            guard actual == expected else { exit(EXIT_FAILURE) }
        }
    }

    @Test("A view whose provider gives Tracker.noOp tracks nothing into the bootstrapped tracker")
    func explicitNoOpDrops() async {
        await #expect(processExitsWith: .success) {
            let tracker = Tracker()
            let expected: [String] = []
            try Tracker.bootstrap(tracker)

            await MainActor.run {
                let delegate = NoOpDelegate()
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                defer { window.close() }
                window.delegate = delegate
                let button = NSButton(title: "Share", target: nil, action: nil)
                window.contentView?.addSubview(button)
                button.track(ShareTapped())

                button.tracker.track(CheckoutStarted())
                button.performClick(nil)
                withExtendedLifetime(delegate) {}
            }
            await tracker.finish()

            var actual: [String] = []
            for await record in tracker.records {
                actual.append(type(of: record.event).name)
            }
            guard actual == expected else { exit(EXIT_FAILURE) }
        }
    }
}
#endif
