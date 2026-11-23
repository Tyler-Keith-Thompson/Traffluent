// AppKit is the Mac's alone; elsewhere this target builds empty.
//
// Each test awaits its tracker's records in order rather than sleeping: discovery tracks after a
// turn of the main run loop, which awaiting gives it. A test that pins what isn't tracked shows a
// later screen arriving first, where the untracked one would have come before it, after waiting
// for turns of the run loop with an observer of its own, ordered after discovery's.
#if os(macOS)
import AppKit
import AppKitTracking
import AutomaticScreenTracking
import Events
import SwiftUI
import SwiftUITracking
import Testing
import Trackers

@MainActor
@Suite("NSWindow.trackScreensAutomatically", .serialized, .timeLimit(.minutes(1)))
struct NSWindowScreenTrackingTests {
    final class TrackingDelegate: NSObject, NSWindowDelegate, TrackerProviding {
        let tracker: Tracker

        init(tracker: Tracker) {
            self.tracker = tracker
        }
    }

    final class PreferencesViewController: NSViewController {
        override func loadView() {
            view = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        }
    }

    final class AccountViewController: NSViewController {
        override func loadView() {
            view = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        }
    }

    /// A container showing one child at a time, as a tab view controller does.
    final class ContainerViewController: NSViewController {
        override func loadView() {
            view = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        }

        func show(_ child: NSViewController) {
            for shown in children {
                shown.view.removeFromSuperview()
                shown.removeFromParent()
            }
            addChild(child)
            view.addSubview(child.view)
        }
    }

    struct SettingsView: View {
        var body: some View {
            Text("Settings")
        }
    }

    @Test("A window's content view controller is a screen, named after its type, and so is the child a container switches to")
    func appKit() async throws {
        let tracker = Tracker()
        var records = tracker.records.makeAsyncIterator()
        let delegate = TrackingDelegate(tracker: tracker)
        let container = ContainerViewController()
        container.show(PreferencesViewController())
        let window = NSWindow(contentViewController: container)
        window.isReleasedWhenClosed = false
        window.delegate = delegate
        window.orderFront(nil)
        defer {
            window.stopTrackingScreensAutomatically()
            window.close()
        }
        let expected = [
            ScreenViewed(screen: "PreferencesViewController"),
            ScreenViewed(screen: "AccountViewController"),
        ]

        window.trackScreensAutomatically()
        var actual: [ScreenViewed] = []
        actual.append(try #require(await records.next()?.event as? ScreenViewed))
        container.show(AccountViewController())
        actual.append(try #require(await records.next()?.event as? ScreenViewed))

        #expect(actual == expected)
    }

    @Test("An NSHostingController's screen is named after its root view's type, of kind swiftUI")
    func swiftUI() async throws {
        let tracker = Tracker()
        var records = tracker.records.makeAsyncIterator()
        let delegate = TrackingDelegate(tracker: tracker)
        let container = ContainerViewController()
        container.show(PreferencesViewController())
        let window = NSWindow(contentViewController: container)
        window.isReleasedWhenClosed = false
        window.delegate = delegate
        window.orderFront(nil)
        defer {
            window.stopTrackingScreensAutomatically()
            window.close()
        }
        let expected = [
            ScreenViewed(screen: "appKit PreferencesViewController"),
            ScreenViewed(screen: "swiftUI SettingsView"),
        ]

        window.trackScreensAutomatically { ScreenViewed(screen: "\($0.kind) \($0.name)") }
        var actual: [ScreenViewed] = []
        actual.append(try #require(await records.next()?.event as? ScreenViewed))
        container.show(NSHostingController(rootView: SettingsView().padding()))
        actual.append(try #require(await records.next()?.event as? ScreenViewed))

        #expect(actual == expected)
    }

    @Test("A screen hidden and shown again tracks again")
    func reappear() async throws {
        let tracker = Tracker()
        var records = tracker.records.makeAsyncIterator()
        let delegate = TrackingDelegate(tracker: tracker)
        let preferences = PreferencesViewController()
        let container = ContainerViewController()
        container.show(preferences)
        let window = NSWindow(contentViewController: container)
        window.isReleasedWhenClosed = false
        window.delegate = delegate
        window.orderFront(nil)
        defer {
            window.stopTrackingScreensAutomatically()
            window.close()
        }
        let expected = [
            ScreenViewed(screen: "PreferencesViewController"),
            ScreenViewed(screen: "AccountViewController"),
            ScreenViewed(screen: "PreferencesViewController"),
        ]

        window.trackScreensAutomatically()
        var actual: [ScreenViewed] = []
        actual.append(try #require(await records.next()?.event as? ScreenViewed))
        container.show(AccountViewController())
        actual.append(try #require(await records.next()?.event as? ScreenViewed))
        container.show(preferences)
        actual.append(try #require(await records.next()?.event as? ScreenViewed))

        #expect(actual == expected)
    }

    @Test("AppKit's own view controllers, such as a plain NSViewController, aren't screens")
    func frameworkController() async throws {
        let tracker = Tracker()
        var records = tracker.records.makeAsyncIterator()
        let delegate = TrackingDelegate(tracker: tracker)
        let plain = NSViewController()
        plain.view = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        let container = ContainerViewController()
        container.show(plain)
        let window = NSWindow(contentViewController: container)
        window.isReleasedWhenClosed = false
        window.delegate = delegate
        window.orderFront(nil)
        defer {
            window.stopTrackingScreensAutomatically()
            window.close()
        }
        let expected = ScreenViewed(screen: "AccountViewController")

        window.trackScreensAutomatically()
        // Two turns of the main run loop, the first past discovery's look at the plain controller.
        for _ in 0..<2 {
            await withCheckedContinuation { (turned: CheckedContinuation<Void, Never>) in
                let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, false, CFIndex.max) { _, _ in turned.resume() }
                CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
            }
        }
        container.show(AccountViewController())
        let actual = try #require(await records.next()?.event as? ScreenViewed)

        #expect(actual == expected)
    }

    @Test("The predicate's event is tracked in place of the default, renaming the screen")
    func rename() async throws {
        let tracker = Tracker()
        var records = tracker.records.makeAsyncIterator()
        let delegate = TrackingDelegate(tracker: tracker)
        let window = NSWindow(contentViewController: PreferencesViewController())
        window.isReleasedWhenClosed = false
        window.delegate = delegate
        window.orderFront(nil)
        defer {
            window.stopTrackingScreensAutomatically()
            window.close()
        }
        let expected = ScreenViewed(screen: "Preferences")

        window.trackScreensAutomatically { screen in
            ScreenViewed(screen: screen.name == "PreferencesViewController" ? "Preferences" : screen.name)
        }
        let actual = try #require(await records.next()?.event as? ScreenViewed)

        #expect(actual == expected)
    }

    @Test("A screen the predicate returns nil for isn't tracked")
    func skip() async throws {
        let tracker = Tracker()
        var records = tracker.records.makeAsyncIterator()
        let delegate = TrackingDelegate(tracker: tracker)
        let container = ContainerViewController()
        container.show(PreferencesViewController())
        let window = NSWindow(contentViewController: container)
        window.isReleasedWhenClosed = false
        window.delegate = delegate
        window.orderFront(nil)
        defer {
            window.stopTrackingScreensAutomatically()
            window.close()
        }
        let expected = ScreenViewed(screen: "AccountViewController")

        window.trackScreensAutomatically { screen in
            screen.name == "PreferencesViewController" ? nil : ScreenViewed(screen: screen.name)
        }
        // Two turns of the main run loop, the first past discovery's look at the skipped screen.
        for _ in 0..<2 {
            await withCheckedContinuation { (turned: CheckedContinuation<Void, Never>) in
                let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, false, CFIndex.max) { _, _ in turned.resume() }
                CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
            }
        }
        container.show(AccountViewController())
        let actual = try #require(await records.next()?.event as? ScreenViewed)

        #expect(actual == expected)
    }

    @Test("Nothing is tracked automatically until trackScreensAutomatically is called")
    func disabledByDefault() async throws {
        let tracker = Tracker()
        var records = tracker.records.makeAsyncIterator()
        let delegate = TrackingDelegate(tracker: tracker)
        let container = ContainerViewController()
        container.show(PreferencesViewController())
        let window = NSWindow(contentViewController: container)
        window.isReleasedWhenClosed = false
        window.delegate = delegate
        window.orderFront(nil)
        defer {
            window.stopTrackingScreensAutomatically()
            window.close()
        }
        // Two turns of the main run loop with the first screen on screen.
        for _ in 0..<2 {
            await withCheckedContinuation { (turned: CheckedContinuation<Void, Never>) in
                let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, false, CFIndex.max) { _, _ in turned.resume() }
                CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
            }
        }
        container.show(AccountViewController())
        let expected = ScreenViewed(screen: "AccountViewController")

        window.trackScreensAutomatically()
        let actual = try #require(await records.next()?.event as? ScreenViewed)

        #expect(actual == expected)
    }

    @Test("With appKit left out of kinds, AppKit screens aren't tracked but SwiftUI ones are")
    func withoutAppKit() async throws {
        let tracker = Tracker()
        var records = tracker.records.makeAsyncIterator()
        let delegate = TrackingDelegate(tracker: tracker)
        let container = ContainerViewController()
        container.show(PreferencesViewController())
        let window = NSWindow(contentViewController: container)
        window.isReleasedWhenClosed = false
        window.delegate = delegate
        window.orderFront(nil)
        defer {
            window.stopTrackingScreensAutomatically()
            window.close()
        }
        let expected = ScreenViewed(screen: "SettingsView")

        window.trackScreensAutomatically(kinds: [.swiftUI])
        // Two turns of the main run loop, the first past discovery's look at the AppKit screen.
        for _ in 0..<2 {
            await withCheckedContinuation { (turned: CheckedContinuation<Void, Never>) in
                let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, false, CFIndex.max) { _, _ in turned.resume() }
                CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
            }
        }
        container.show(NSHostingController(rootView: SettingsView()))
        let actual = try #require(await records.next()?.event as? ScreenViewed)

        #expect(actual == expected)
    }

    @Test("With swiftUI left out of kinds, SwiftUI screens aren't tracked but AppKit ones are")
    func withoutSwiftUI() async throws {
        let tracker = Tracker()
        var records = tracker.records.makeAsyncIterator()
        let delegate = TrackingDelegate(tracker: tracker)
        let container = ContainerViewController()
        container.show(NSHostingController(rootView: SettingsView()))
        let window = NSWindow(contentViewController: container)
        window.isReleasedWhenClosed = false
        window.delegate = delegate
        window.orderFront(nil)
        defer {
            window.stopTrackingScreensAutomatically()
            window.close()
        }
        let expected = ScreenViewed(screen: "AccountViewController")

        window.trackScreensAutomatically(kinds: [.appKit])
        // Two turns of the main run loop, the first past discovery's look at the SwiftUI screen.
        for _ in 0..<2 {
            await withCheckedContinuation { (turned: CheckedContinuation<Void, Never>) in
                let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, false, CFIndex.max) { _, _ in turned.resume() }
                CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
            }
        }
        container.show(AccountViewController())
        let actual = try #require(await records.next()?.event as? ScreenViewed)

        #expect(actual == expected)
    }

    @Test("A SwiftUI screen given trackScreen tracks only its own ScreenViewed, not an automatic one too")
    func manualScreenWins() async throws {
        let tracker = Tracker()
        var records = tracker.records.makeAsyncIterator()
        let delegate = TrackingDelegate(tracker: tracker)
        let container = ContainerViewController()
        container.show(PreferencesViewController())
        let window = NSWindow(contentViewController: container)
        window.isReleasedWhenClosed = false
        window.delegate = delegate
        window.orderFront(nil)
        defer {
            window.stopTrackingScreensAutomatically()
            window.close()
        }
        let expected = [
            ScreenViewed(screen: "PreferencesViewController"),
            ScreenViewed(screen: "Settings"),
            ScreenViewed(screen: "AccountViewController"),
        ]

        window.trackScreensAutomatically()
        var actual: [ScreenViewed] = []
        actual.append(try #require(await records.next()?.event as? ScreenViewed))
        // AppKit has no environment bridge, so the SwiftUI view gets the tracker in its own.
        container.show(NSHostingController(rootView: SettingsView().trackScreen("Settings").tracker(tracker)))
        actual.append(try #require(await records.next()?.event as? ScreenViewed))
        container.show(AccountViewController())
        actual.append(try #require(await records.next()?.event as? ScreenViewed))

        #expect(actual == expected)
    }

    @Test("Each window's screens go through the tracker its views find, so two windows keep theirs apart")
    func windowTrackers() async throws {
        let preferencesTracker = Tracker()
        let accountTracker = Tracker()
        var preferencesRecords = preferencesTracker.records.makeAsyncIterator()
        var accountRecords = accountTracker.records.makeAsyncIterator()
        let preferencesDelegate = TrackingDelegate(tracker: preferencesTracker)
        let accountDelegate = TrackingDelegate(tracker: accountTracker)
        let preferencesWindow = NSWindow(contentViewController: PreferencesViewController())
        preferencesWindow.isReleasedWhenClosed = false
        preferencesWindow.delegate = preferencesDelegate
        let accountWindow = NSWindow(contentViewController: AccountViewController())
        accountWindow.isReleasedWhenClosed = false
        accountWindow.delegate = accountDelegate
        preferencesWindow.orderFront(nil)
        accountWindow.orderFront(nil)
        defer {
            preferencesWindow.close()
            accountWindow.close()
        }
        let expectedPreferences = [ScreenViewed(screen: "PreferencesViewController")]
        let expectedAccount = [ScreenViewed(screen: "AccountViewController")]

        preferencesWindow.trackScreensAutomatically()
        accountWindow.trackScreensAutomatically()
        let firstPreferences = try #require(await preferencesRecords.next()?.event as? ScreenViewed)
        let firstAccount = try #require(await accountRecords.next()?.event as? ScreenViewed)
        preferencesWindow.stopTrackingScreensAutomatically()
        accountWindow.stopTrackingScreensAutomatically()
        await preferencesTracker.finish()
        await accountTracker.finish()

        var actualPreferences = [firstPreferences]
        while let record = await preferencesRecords.next() {
            actualPreferences.append(try #require(record.event as? ScreenViewed))
        }
        var actualAccount = [firstAccount]
        while let record = await accountRecords.next() {
            actualAccount.append(try #require(record.event as? ScreenViewed))
        }
        #expect(actualPreferences == expectedPreferences)
        #expect(actualAccount == expectedAccount)
    }

    @Test("A screen view's call site is where trackScreensAutomatically is called")
    func callSite() async throws {
        let tracker = Tracker()
        var records = tracker.records.makeAsyncIterator()
        let delegate = TrackingDelegate(tracker: tracker)
        let window = NSWindow(contentViewController: PreferencesViewController())
        window.isReleasedWhenClosed = false
        window.delegate = delegate
        window.orderFront(nil)
        defer {
            window.stopTrackingScreensAutomatically()
            window.close()
        }
        let expectedLine = #line + 3
        let expectedFileID = #fileID

        window.trackScreensAutomatically()
        let actual = try #require(await records.next()?.sourceLocation)

        #expect(actual.line == expectedLine)
        #expect(actual.fileID == expectedFileID)
        #expect(actual.function == "callSite()")
    }

    @Test("After stopTrackingScreensAutomatically, screens aren't tracked; a later call tracks those on screen then")
    func stop() async throws {
        let tracker = Tracker()
        var records = tracker.records.makeAsyncIterator()
        let delegate = TrackingDelegate(tracker: tracker)
        let container = ContainerViewController()
        container.show(PreferencesViewController())
        let window = NSWindow(contentViewController: container)
        window.isReleasedWhenClosed = false
        window.delegate = delegate
        window.orderFront(nil)
        defer {
            window.stopTrackingScreensAutomatically()
            window.close()
        }
        let expected = [
            ScreenViewed(screen: "PreferencesViewController"),
            ScreenViewed(screen: "SettingsView"),
        ]

        window.trackScreensAutomatically()
        var actual: [ScreenViewed] = []
        actual.append(try #require(await records.next()?.event as? ScreenViewed))
        window.stopTrackingScreensAutomatically()
        container.show(AccountViewController())
        // Two turns of the main run loop with the account screen on screen.
        for _ in 0..<2 {
            await withCheckedContinuation { (turned: CheckedContinuation<Void, Never>) in
                let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, false, CFIndex.max) { _, _ in turned.resume() }
                CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
            }
        }
        container.show(NSHostingController(rootView: SettingsView()))
        window.trackScreensAutomatically()
        actual.append(try #require(await records.next()?.event as? ScreenViewed))

        #expect(actual == expected)
    }

    @Test("Calling trackScreensAutomatically again replaces the earlier call, without tracking again the screens on screen")
    func replace() async throws {
        let tracker = Tracker()
        var records = tracker.records.makeAsyncIterator()
        let delegate = TrackingDelegate(tracker: tracker)
        let container = ContainerViewController()
        container.show(PreferencesViewController())
        let window = NSWindow(contentViewController: container)
        window.isReleasedWhenClosed = false
        window.delegate = delegate
        window.orderFront(nil)
        defer {
            window.stopTrackingScreensAutomatically()
            window.close()
        }
        let expected = [
            ScreenViewed(screen: "first PreferencesViewController"),
            ScreenViewed(screen: "second AccountViewController"),
        ]

        window.trackScreensAutomatically { ScreenViewed(screen: "first \($0.name)") }
        var actual: [ScreenViewed] = []
        actual.append(try #require(await records.next()?.event as? ScreenViewed))
        window.trackScreensAutomatically { ScreenViewed(screen: "second \($0.name)") }
        // Two turns of the main run loop with the first screen still on screen.
        for _ in 0..<2 {
            await withCheckedContinuation { (turned: CheckedContinuation<Void, Never>) in
                let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, false, CFIndex.max) { _, _ in turned.resume() }
                CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
            }
        }
        container.show(AccountViewController())
        actual.append(try #require(await records.next()?.event as? ScreenViewed))

        #expect(actual == expected)
    }

    @Test("A window ordered out has no screens, and its screen tracks again when it is shown")
    func orderedOut() async throws {
        let tracker = Tracker()
        var records = tracker.records.makeAsyncIterator()
        let delegate = TrackingDelegate(tracker: tracker)
        let window = NSWindow(contentViewController: PreferencesViewController())
        window.isReleasedWhenClosed = false
        window.delegate = delegate
        window.orderFront(nil)
        defer {
            window.stopTrackingScreensAutomatically()
            window.close()
        }
        let expected = [
            ScreenViewed(screen: "PreferencesViewController"),
            ScreenViewed(screen: "PreferencesViewController"),
        ]

        window.trackScreensAutomatically()
        var actual: [ScreenViewed] = []
        actual.append(try #require(await records.next()?.event as? ScreenViewed))
        window.orderOut(nil)
        // Two turns of the main run loop with the window ordered out.
        for _ in 0..<2 {
            await withCheckedContinuation { (turned: CheckedContinuation<Void, Never>) in
                let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, false, CFIndex.max) { _, _ in turned.resume() }
                CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
            }
        }
        window.orderFront(nil)
        actual.append(try #require(await records.next()?.event as? ScreenViewed))

        #expect(actual == expected)
    }
}
#endif
