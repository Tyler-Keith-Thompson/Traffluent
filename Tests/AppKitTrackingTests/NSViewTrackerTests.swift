// AppKit is the Mac's alone; elsewhere this target builds empty.
#if os(macOS)
import AppKit
import AppKitTracking
import Events
import Testing
import Trackers

@MainActor
@Suite("NSView.tracker", .serialized, .timeLimit(.minutes(1)))
struct NSViewTrackerTests {
    struct CheckoutStarted: Event, Equatable {}

    final class CheckoutWindowController: NSWindowController, TrackerProviding {
        let tracker: Tracker
        let button = NSButton(title: "Check out", target: nil, action: nil)

        init(tracker: Tracker) {
            self.tracker = tracker
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            super.init(window: window)
            button.target = self
            button.action = #selector(checkOut(_:))
            window.contentView?.addSubview(button)
        }

        required init?(coder: NSCoder) { nil }

        @objc func checkOut(_ sender: NSButton) {
            sender.tracker.track(CheckoutStarted())
        }
    }

    final class ScreenViewController: NSViewController, TrackerProviding {
        let tracker: Tracker

        init(tracker: Tracker) {
            self.tracker = tracker
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) { nil }

        override func loadView() {
            view = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        }
    }

    final class TrackingDelegate: NSObject, NSWindowDelegate, NSApplicationDelegate, TrackerProviding {
        let tracker: Tracker

        init(tracker: Tracker) {
            self.tracker = tracker
        }
    }

    @Test("A view in no window, below no provider, tracks through Tracker.noOp, which drops every event")
    func noProvider() async {
        let sut = NSView().tracker
        let expected = 0

        sut.track(CheckoutStarted())
        await sut.finish()

        var actual = 0
        for await _ in sut.records {
            actual += 1
        }
        #expect(actual == expected)
    }

    @Test("A target-action callback in a window controller's window tracks through the window controller's tracker")
    func windowController() async throws {
        let tracker = Tracker()
        let controller = CheckoutWindowController(tracker: tracker)
        defer { controller.close() }
        let expected = [CheckoutStarted()]

        controller.button.performClick(nil)
        await tracker.finish()

        var actual: [CheckoutStarted] = []
        for await record in tracker.records {
            actual.append(try #require(record.event as? CheckoutStarted))
        }
        #expect(actual == expected)
    }

    @Test("Two windows with a tracker each deliver only their own events")
    func twoWindows() async {
        let firstTracker = Tracker()
        let secondTracker = Tracker()
        let first = CheckoutWindowController(tracker: firstTracker)
        defer { first.close() }
        let second = CheckoutWindowController(tracker: secondTracker)
        defer { second.close() }
        let expectedFirst = 1
        let expectedSecond = 2

        first.button.performClick(nil)
        second.button.performClick(nil)
        second.button.performClick(nil)
        await firstTracker.finish()
        await secondTracker.finish()

        var actualFirst = 0
        for await _ in firstTracker.records {
            actualFirst += 1
        }
        var actualSecond = 0
        for await _ in secondTracker.records {
            actualSecond += 1
        }
        #expect(actualFirst == expectedFirst)
        #expect(actualSecond == expectedSecond)
    }

    @Test("A view controller that provides a tracker gives the views below it its tracker, over its window controller's")
    func viewController() async {
        let windowTracker = Tracker()
        let screenTracker = Tracker()
        let controller = CheckoutWindowController(tracker: windowTracker)
        defer { controller.close() }
        let screen = ScreenViewController(tracker: screenTracker)
        controller.window?.contentView?.addSubview(screen.view)
        let sut = NSView()
        screen.view.addSubview(sut)
        let expectedScreen = 1
        let expectedWindow = 0

        sut.tracker.track(CheckoutStarted())
        await windowTracker.finish()
        await screenTracker.finish()

        var actualScreen = 0
        for await _ in screenTracker.records {
            actualScreen += 1
        }
        var actualWindow = 0
        for await _ in windowTracker.records {
            actualWindow += 1
        }
        #expect(actualScreen == expectedScreen)
        #expect(actualWindow == expectedWindow)
    }

    @Test("A window with no provider in its responder chain finds its delegate's tracker")
    func windowDelegate() async {
        let tracker = Tracker()
        let delegate = TrackingDelegate(tracker: tracker)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.delegate = delegate
        defer { window.close() }
        let sut = NSView()
        window.contentView?.addSubview(sut)
        let expected = 1

        sut.tracker.track(CheckoutStarted())
        await tracker.finish()

        var actual = 0
        for await _ in tracker.records {
            actual += 1
        }
        #expect(actual == expected)
    }

    @Test("A provider in the responder chain comes before the window's delegate")
    func chainBeforeDelegate() async {
        let chainTracker = Tracker()
        let delegateTracker = Tracker()
        let controller = CheckoutWindowController(tracker: chainTracker)
        defer { controller.close() }
        let delegate = TrackingDelegate(tracker: delegateTracker)
        controller.window?.delegate = delegate
        let expectedChain = 1
        let expectedDelegate = 0

        controller.button.performClick(nil)
        await chainTracker.finish()
        await delegateTracker.finish()

        var actualChain = 0
        for await _ in chainTracker.records {
            actualChain += 1
        }
        var actualDelegate = 0
        for await _ in delegateTracker.records {
            actualDelegate += 1
        }
        #expect(actualChain == expectedChain)
        #expect(actualDelegate == expectedDelegate)
    }

    @Test("A window's delegate comes before the application's delegate")
    func windowDelegateBeforeApplicationDelegate() async {
        let windowTracker = Tracker()
        let applicationTracker = Tracker()
        let windowDelegate = TrackingDelegate(tracker: windowTracker)
        let applicationDelegate = TrackingDelegate(tracker: applicationTracker)
        let application = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.delegate = windowDelegate
        defer { window.close() }
        let sut = NSView()
        window.contentView?.addSubview(sut)
        let expectedWindow = 1
        let expectedApplication = 0

        // The application's delegate is the process's, so it is put back before the test awaits
        // and another test could run.
        let previous = application.delegate
        application.delegate = applicationDelegate
        sut.tracker.track(CheckoutStarted())
        application.delegate = previous
        await windowTracker.finish()
        await applicationTracker.finish()

        var actualWindow = 0
        for await _ in windowTracker.records {
            actualWindow += 1
        }
        var actualApplication = 0
        for await _ in applicationTracker.records {
            actualApplication += 1
        }
        #expect(actualWindow == expectedWindow)
        #expect(actualApplication == expectedApplication)
    }

    @Test("A window with no provider in its responder chain or delegate finds the application delegate's tracker")
    func applicationDelegate() async {
        let tracker = Tracker()
        let delegate = TrackingDelegate(tracker: tracker)
        let application = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let sut = NSView()
        window.contentView?.addSubview(sut)
        let expected = 1

        // The application's delegate is the process's, so it is put back before the test awaits
        // and another test could run.
        let previous = application.delegate
        application.delegate = delegate
        sut.tracker.track(CheckoutStarted())
        application.delegate = previous
        await tracker.finish()

        var actual = 0
        for await _ in tracker.records {
            actual += 1
        }
        #expect(actual == expected)
    }

    @Test("A view moved to another window tracks through that window's tracker")
    func movedView() async {
        let firstTracker = Tracker()
        let secondTracker = Tracker()
        let first = CheckoutWindowController(tracker: firstTracker)
        defer { first.close() }
        let second = CheckoutWindowController(tracker: secondTracker)
        defer { second.close() }
        let expectedFirst = 0
        let expectedSecond = 1

        second.window?.contentView?.addSubview(first.button)
        first.button.performClick(nil)
        await firstTracker.finish()
        await secondTracker.finish()

        var actualFirst = 0
        for await _ in firstTracker.records {
            actualFirst += 1
        }
        var actualSecond = 0
        for await _ in secondTracker.records {
            actualSecond += 1
        }
        #expect(actualFirst == expectedFirst)
        #expect(actualSecond == expectedSecond)
    }
}
#endif
