// UIKit's traits are on iOS, which these tests run on, in the simulator's test host
// (SIMULATOR_TESTS in scripts/modules.py); elsewhere this target builds empty.
#if canImport(UIKit) && !os(watchOS)
import Events
import Testing
import Trackers
import UIKit
import UIKitTracking

@MainActor
@Suite("TrackerTrait", .serialized, .timeLimit(.minutes(1)))
struct TrackerTraitTests {
    struct CheckoutStarted: Event, Equatable {}

    final class CheckoutViewController: UIViewController {
        let button = UIButton(type: .system)

        override func viewDidLoad() {
            super.viewDidLoad()
            button.frame = CGRect(x: 0, y: 0, width: 100, height: 44)
            button.addTarget(self, action: #selector(checkOut(_:)), for: .touchUpInside)
            view.addSubview(button)
        }

        @objc func checkOut(_ sender: UIButton) {
            sender.traitCollection.tracker.track(CheckoutStarted())
        }
    }

    @Test("Without a tracker set, a trait collection's tracker drops every event")
    func defaultDrops() async {
        let sut = UITraitCollection().tracker
        let expected = 0

        sut.track(CheckoutStarted())
        await sut.finish()

        var actual = 0
        for await _ in sut.records {
            actual += 1
        }
        #expect(actual == expected)
    }

    @Test("A tracker set on trait overrides reads back from them")
    func overridesReadBack() async {
        let tracker = Tracker()
        let controller = UIViewController()
        controller.traitOverrides.tracker = tracker
        let expected = 1

        controller.traitOverrides.tracker.track(CheckoutStarted())
        await tracker.finish()

        var actual = 0
        for await _ in tracker.records {
            actual += 1
        }
        #expect(actual == expected)
    }

    @Test("A target-action callback in a hosted view controller tracks through the tracker set on its scene")
    func sceneTracker() async throws {
        let tracker = Tracker()
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        scene.traitOverrides.tracker = tracker
        defer { scene.traitOverrides.remove(TrackerTrait.self) }
        let window = UIWindow(windowScene: scene)
        let controller = CheckoutViewController()
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        window.layoutIfNeeded()
        let expected = [CheckoutStarted()]

        controller.button.sendActions(for: .touchUpInside)
        await tracker.finish()

        var actual: [CheckoutStarted] = []
        for await record in tracker.records {
            actual.append(try #require(record.event as? CheckoutStarted))
        }
        #expect(actual == expected)
    }

    @Test("A tracker set on a view controller's trait overrides reaches the views below it, over its scene's")
    func viewControllerOverrides() async throws {
        let sceneTracker = Tracker()
        let controllerTracker = Tracker()
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        scene.traitOverrides.tracker = sceneTracker
        defer { scene.traitOverrides.remove(TrackerTrait.self) }
        let window = UIWindow(windowScene: scene)
        let controller = CheckoutViewController()
        controller.traitOverrides.tracker = controllerTracker
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        window.layoutIfNeeded()
        let expectedController = 1
        let expectedScene = 0

        controller.button.sendActions(for: .touchUpInside)
        await sceneTracker.finish()
        await controllerTracker.finish()

        var actualController = 0
        for await _ in controllerTracker.records {
            actualController += 1
        }
        var actualScene = 0
        for await _ in sceneTracker.records {
            actualScene += 1
        }
        #expect(actualController == expectedController)
        #expect(actualScene == expectedScene)
    }

    @Test("Two windows with a tracker each deliver only their own events")
    func twoWindows() async throws {
        let firstTracker = Tracker()
        let secondTracker = Tracker()
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let firstWindow = UIWindow(windowScene: scene)
        let firstController = CheckoutViewController()
        firstController.traitOverrides.tracker = firstTracker
        firstWindow.rootViewController = firstController
        firstWindow.isHidden = false
        defer { firstWindow.isHidden = true }
        let secondWindow = UIWindow(windowScene: scene)
        let secondController = CheckoutViewController()
        secondController.traitOverrides.tracker = secondTracker
        secondWindow.rootViewController = secondController
        secondWindow.isHidden = false
        defer { secondWindow.isHidden = true }
        firstWindow.layoutIfNeeded()
        secondWindow.layoutIfNeeded()
        let expectedFirst = 1
        let expectedSecond = 2

        firstController.button.sendActions(for: .touchUpInside)
        secondController.button.sendActions(for: .touchUpInside)
        secondController.button.sendActions(for: .touchUpInside)
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
