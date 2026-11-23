#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit
import LifecycleTracking
import Testing
import Trackers

@Suite("trackLifecycle: transitions on macOS", .timeLimit(.minutes(1)))
struct TransitionTests {
    @Test("Resigning active tracks a move to the background, becoming active again an open from the background")
    func backgroundAndBack() async {
        let center = NotificationCenter()
        let tracker = Tracker()
        let expected = [
            "ApplicationOpened(fromBackground: false)",
            "ApplicationBackgrounded()",
            "ApplicationOpened(fromBackground: true)",
        ]

        let sut = tracker.trackLifecycle(kinds: [.opened, .backgrounded], version: nil, versionStore: InMemoryVersionStore(), notificationCenter: center)
        center.post(name: NSApplication.didResignActiveNotification, object: nil)
        center.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        await sut.finish()
        await tracker.finish()

        var actual: [String] = []
        for await record in tracker.records {
            actual.append(String(describing: record.event))
        }
        #expect(actual == expected)
    }

    @Test("Each transition tracks once, however many times it is reported")
    func oncePerTransition() async {
        let center = NotificationCenter()
        let tracker = Tracker()
        let expected = [
            "ApplicationOpened(fromBackground: false)",
            "ApplicationBackgrounded()",
            "ApplicationOpened(fromBackground: true)",
            "ApplicationBackgrounded()",
            "ApplicationTerminated()",
        ]

        let sut = tracker.trackLifecycle(version: nil, versionStore: InMemoryVersionStore(), notificationCenter: center)
        // Already in the foreground: becoming active as the app launches tracks no second open.
        center.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        center.post(name: NSApplication.didResignActiveNotification, object: nil)
        center.post(name: NSApplication.didResignActiveNotification, object: nil)
        center.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        center.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        center.post(name: NSApplication.didResignActiveNotification, object: nil)
        center.post(name: NSApplication.willTerminateNotification, object: nil)
        center.post(name: NSApplication.willTerminateNotification, object: nil)
        // Terminated: nothing more is tracked, finishing included.
        center.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        center.post(name: NSApplication.didResignActiveNotification, object: nil)
        await sut.finish()
        await tracker.finish()

        var actual: [String] = []
        for await record in tracker.records {
            actual.append(String(describing: record.event))
        }
        #expect(actual == expected)
    }

    @Test("Termination tracks an end from the background too")
    func terminatedFromBackground() async {
        let center = NotificationCenter()
        let tracker = Tracker()
        let expected = ["ApplicationBackgrounded()", "ApplicationTerminated()"]

        let sut = tracker.trackLifecycle(kinds: [.backgrounded, .terminated], version: nil, versionStore: InMemoryVersionStore(), notificationCenter: center)
        center.post(name: NSApplication.didResignActiveNotification, object: nil)
        center.post(name: NSApplication.willTerminateNotification, object: nil)
        await sut.finish()
        await tracker.finish()

        var actual: [String] = []
        for await record in tracker.records {
            actual.append(String(describing: record.event))
        }
        #expect(actual == expected)
    }

    @Test("Each kind turned off tracks nothing of that kind, the others as before", arguments: LifecycleObservation.Kind.allCases)
    func kindOff(kind: LifecycleObservation.Kind) async {
        let center = NotificationCenter()
        let tracker = Tracker()
        let all: [(LifecycleObservation.Kind, String)] = [
            (.installed, "ApplicationInstalled(version: \"1.0\")"),
            (.opened, "ApplicationOpened(fromBackground: false)"),
            (.backgrounded, "ApplicationBackgrounded()"),
            (.opened, "ApplicationOpened(fromBackground: true)"),
            (.terminated, "ApplicationTerminated()"),
        ]
        let expected = all.filter { $0.0 != kind }.map(\.1)
        let kinds = Set(LifecycleObservation.Kind.allCases).subtracting([kind])

        let sut = tracker.trackLifecycle(kinds: kinds, version: "1.0", versionStore: InMemoryVersionStore(), notificationCenter: center)
        center.post(name: NSApplication.didResignActiveNotification, object: nil)
        center.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        center.post(name: NSApplication.willTerminateNotification, object: nil)
        await sut.finish()
        await tracker.finish()

        var actual: [String] = []
        for await record in tracker.records {
            actual.append(String(describing: record.event))
        }
        #expect(actual == expected)
    }

    @Test("With every kind off, nothing is tracked")
    func everyKindOff() async {
        let center = NotificationCenter()
        let tracker = Tracker()

        let sut = tracker.trackLifecycle(kinds: [], version: "1.0", versionStore: InMemoryVersionStore(), notificationCenter: center)
        center.post(name: NSApplication.didResignActiveNotification, object: nil)
        center.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        center.post(name: NSApplication.willTerminateNotification, object: nil)
        await sut.finish()
        await tracker.finish()

        var actual: [String] = []
        for await record in tracker.records {
            actual.append(String(describing: record.event))
        }
        #expect(actual.isEmpty)
    }

    @Test("Once cancelled, notifications track nothing, and finishing tracks no end")
    func cancelled() async {
        let center = NotificationCenter()
        let tracker = Tracker()

        let sut = tracker.trackLifecycle(kinds: [.backgrounded, .terminated], version: nil, versionStore: InMemoryVersionStore(), notificationCenter: center)
        sut.cancel()
        center.post(name: NSApplication.didResignActiveNotification, object: nil)
        center.post(name: NSApplication.willTerminateNotification, object: nil)
        await sut.finish()
        await tracker.finish()

        var actual: [String] = []
        for await record in tracker.records {
            actual.append(String(describing: record.event))
        }
        #expect(actual.isEmpty)
    }

    @Test("A released observation stops observing")
    func released() async {
        let center = NotificationCenter()
        let tracker = Tracker()

        _ = tracker.trackLifecycle(kinds: [.backgrounded, .terminated], version: nil, versionStore: InMemoryVersionStore(), notificationCenter: center)
        center.post(name: NSApplication.didResignActiveNotification, object: nil)
        center.post(name: NSApplication.willTerminateNotification, object: nil)
        await tracker.finish()

        var actual: [String] = []
        for await record in tracker.records {
            actual.append(String(describing: record.event))
        }
        #expect(actual.isEmpty)
    }
}
#endif
