#if os(macOS)
import AppKit
import AppKitTracking
import Events
import Testing
import Trackers

@MainActor
@Suite("NSControl.track(_:)", .serialized, .timeLimit(.minutes(1)))
struct NSControlTrackTests {
    struct ShareTapped: Event, Equatable {}

    struct LinkCopied: Event, Equatable {}

    struct Shared: Event, Equatable {}

    final class ShareWindowController: NSWindowController, TrackerProviding {
        let tracker: Tracker

        init(tracker: Tracker) {
            self.tracker = tracker
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            super.init(window: window)
        }

        required init?(coder: NSCoder) { nil }

        @objc func share(_ sender: NSButton) {
            tracker.track(Shared())
        }
    }

    final class SharingDelegate: NSObject, NSApplicationDelegate {
        let tracker: Tracker

        init(tracker: Tracker) {
            self.tracker = tracker
        }

        @objc func share(_ sender: NSButton) {
            tracker.track(Shared())
        }
    }

    @Test("Each click tracks the event once, before the control's own action, which still runs")
    func click() async {
        let tracker = Tracker()
        let controller = ShareWindowController(tracker: tracker)
        defer { controller.close() }
        let sut = NSButton(title: "Share", target: controller, action: #selector(ShareWindowController.share(_:)))
        controller.window?.contentView?.addSubview(sut)
        sut.track(ShareTapped())
        let expected = ["ShareTapped", "Shared", "ShareTapped", "Shared"]

        sut.performClick(nil)
        sut.performClick(nil)
        await tracker.finish()

        var actual: [String] = []
        for await record in tracker.records {
            actual.append(type(of: record.event).name)
        }
        #expect(actual == expected)
    }

    @Test("A control with no target still sends its action up the responder chain, to the application's delegate")
    func noTarget() async {
        let tracker = Tracker()
        let controller = ShareWindowController(tracker: Tracker())
        defer { controller.close() }
        let delegate = SharingDelegate(tracker: tracker)
        let application = NSApplication.shared
        let sut = NSButton(title: "Share", target: nil, action: #selector(SharingDelegate.share(_:)))
        controller.window?.contentView?.addSubview(sut)
        sut.track(ShareTapped())
        let expected = ["Shared"]

        // The application's delegate is the process's, so it is put back before the test awaits
        // and another test could run.
        let previous = application.delegate
        application.delegate = delegate
        sut.performClick(nil)
        application.delegate = previous
        await tracker.finish()

        var actual: [String] = []
        for await record in tracker.records {
            actual.append(type(of: record.event).name)
        }
        #expect(actual == expected)
    }

    @Test("Tracking twice tracks both events, the newest first, then the control's own action")
    func twice() async {
        let tracker = Tracker()
        let controller = ShareWindowController(tracker: tracker)
        defer { controller.close() }
        let sut = NSButton(title: "Share", target: controller, action: #selector(ShareWindowController.share(_:)))
        controller.window?.contentView?.addSubview(sut)
        sut.track(ShareTapped())
        sut.track(LinkCopied())
        let expected = ["LinkCopied", "ShareTapped", "Shared"]

        sut.performClick(nil)
        await tracker.finish()

        var actual: [String] = []
        for await record in tracker.records {
            actual.append(type(of: record.event).name)
        }
        #expect(actual == expected)
    }

    @Test("A control moved to another window tracks through that window's tracker")
    func moved() async {
        let firstTracker = Tracker()
        let secondTracker = Tracker()
        let first = ShareWindowController(tracker: firstTracker)
        defer { first.close() }
        let second = ShareWindowController(tracker: secondTracker)
        defer { second.close() }
        let sut = NSButton(title: "Share", target: nil, action: nil)
        first.window?.contentView?.addSubview(sut)
        sut.track(ShareTapped())
        let expectedFirst = 0
        let expectedSecond = 1

        second.window?.contentView?.addSubview(sut)
        sut.performClick(nil)
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

    @Test("The record's call site is where track is called")
    func callSite() async throws {
        let tracker = Tracker()
        let controller = ShareWindowController(tracker: tracker)
        defer { controller.close() }
        let sut = NSButton(title: "Share", target: nil, action: nil)
        controller.window?.contentView?.addSubview(sut)
        let expectedLine = #line + 1
        sut.track(ShareTapped())
        let expectedFileID = #fileID
        let expectedFunction = #function

        sut.performClick(nil)
        await tracker.finish()

        var records = tracker.records.makeAsyncIterator()
        let actual = try #require(await records.next()?.sourceLocation)
        #expect(actual.line == expectedLine)
        #expect(actual.fileID == expectedFileID)
        #expect(actual.function == expectedFunction)
    }
}
#endif
