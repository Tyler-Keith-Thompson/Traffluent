#if canImport(UIKit) && !os(watchOS)
import Events
import Testing
import Trackers
import UIKit
import UIKitTracking

@MainActor
@Suite("UIControl.track(_:for:)", .serialized, .timeLimit(.minutes(1)))
struct UIControlTrackTests {
    struct ShareTapped: Event, Equatable {}

    struct Shared: Event, Equatable {}

    @Test("Each primary action tracks the event once, and the control still runs its own action")
    func primaryAction() async throws {
        let tracker = Tracker()
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        let controller = UIViewController()
        controller.traitOverrides.tracker = tracker
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        let sut = UIButton(primaryAction: UIAction { _ in tracker.track(Shared()) })
        controller.view.addSubview(sut)
        sut.track(ShareTapped())
        window.layoutIfNeeded()
        let expected = ["Shared", "ShareTapped", "Shared", "ShareTapped"]

        sut.sendActions(for: .primaryActionTriggered)
        sut.sendActions(for: .primaryActionTriggered)
        await tracker.finish()

        var actual: [String] = []
        for await record in tracker.records {
            actual.append(type(of: record.event).name)
        }
        #expect(actual == expected)
    }

    @Test("Control events other than the ones given track nothing")
    func otherControlEvents() async throws {
        let tracker = Tracker()
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        let controller = UIViewController()
        controller.traitOverrides.tracker = tracker
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        let sut = UISwitch()
        controller.view.addSubview(sut)
        sut.track(ShareTapped(), for: .valueChanged)
        window.layoutIfNeeded()
        let expected = 1

        sut.sendActions(for: .touchUpInside)
        sut.sendActions(for: .valueChanged)
        await tracker.finish()

        var actual = 0
        for await _ in tracker.records {
            actual += 1
        }
        #expect(actual == expected)
    }

    @Test("Removing the returned action stops tracking")
    func removeAction() async throws {
        let tracker = Tracker()
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        let controller = UIViewController()
        controller.traitOverrides.tracker = tracker
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        let sut = UIButton(type: .system)
        controller.view.addSubview(sut)
        let action = sut.track(ShareTapped())
        window.layoutIfNeeded()
        let expected = 0

        sut.removeAction(action, for: .primaryActionTriggered)
        sut.sendActions(for: .primaryActionTriggered)
        await tracker.finish()

        var actual = 0
        for await _ in tracker.records {
            actual += 1
        }
        #expect(actual == expected)
    }

    @Test("A control moved to another window tracks through that window's tracker")
    func movedControl() async throws {
        let firstTracker = Tracker()
        let secondTracker = Tracker()
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let firstWindow = UIWindow(windowScene: scene)
        let firstController = UIViewController()
        firstController.traitOverrides.tracker = firstTracker
        firstWindow.rootViewController = firstController
        firstWindow.isHidden = false
        defer { firstWindow.isHidden = true }
        let secondWindow = UIWindow(windowScene: scene)
        let secondController = UIViewController()
        secondController.traitOverrides.tracker = secondTracker
        secondWindow.rootViewController = secondController
        secondWindow.isHidden = false
        defer { secondWindow.isHidden = true }
        let sut = UIButton(type: .system)
        firstController.view.addSubview(sut)
        sut.track(ShareTapped())
        firstWindow.layoutIfNeeded()
        let expectedFirst = 0
        let expectedSecond = 1

        secondController.view.addSubview(sut)
        secondWindow.layoutIfNeeded()
        sut.sendActions(for: .primaryActionTriggered)
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
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        let controller = UIViewController()
        controller.traitOverrides.tracker = tracker
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        let sut = UIButton(type: .system)
        controller.view.addSubview(sut)
        let expectedLine = #line + 1
        sut.track(ShareTapped())
        let expectedFileID = #fileID
        let expectedFunction = #function
        window.layoutIfNeeded()

        sut.sendActions(for: .primaryActionTriggered)
        await tracker.finish()

        var records = tracker.records.makeAsyncIterator()
        let actual = try #require(await records.next()?.sourceLocation)
        #expect(actual.line == expectedLine)
        #expect(actual.fileID == expectedFileID)
        #expect(actual.function == expectedFunction)
    }
}
#endif
