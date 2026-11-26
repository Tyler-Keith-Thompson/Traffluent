// The example of AutomaticControlTracking's landing article
// (Sources/AutomaticControlTracking/AutomaticControlTracking.docc/AutomaticControlTracking.md),
// verbatim. It needs UIKit, so it runs here, in the simulator, in the suite that shares the test
// host's window scene. UIKit has no public way to make a touch, so this pins only that an action
// sent without one tracks nothing; the touches themselves are AutomaticControlTrackingUITests'.
#if canImport(UIKit) && !os(watchOS)
import AutomaticControlTracking
import Events
import Testing
import Trackers
import UIKit
import UIKitTracking

extension UIWindowSceneScreenTrackingTests {
    struct Marker: Event {}

    final class CartViewController: UIViewController {
        let checkOut = UIButton(configuration: .filled())

        override func viewDidLoad() {
            super.viewDidLoad()
            checkOut.accessibilityIdentifier = "checkout-button"  // tracked as ControlActivated(control: "checkout-button", kind: "UIButton")
            view.addSubview(checkOut)
        }
    }

    @Test("AutomaticControlTracking module example")
    func controlTrackingModuleExample() async throws {
        let tracker = Tracker()
        let windowScene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: windowScene)
        let controller = CartViewController()
        window.rootViewController = controller
        window.isHidden = false
        defer {
            windowScene.stopTrackingControlsAutomatically()
            windowScene.traitOverrides.remove(TrackerTrait.self)
            window.isHidden = true
        }

        // In the scene delegate's scene(_:willConnectTo:options:), beside the scene's tracker:
        windowScene.traitOverrides.tracker = tracker
        windowScene.trackControlsAutomatically()

        controller.checkOut.sendActions(for: .primaryActionTriggered)
        tracker.track(Marker())
        await tracker.finish()
        var actual: [String] = []
        for await record in tracker.records {
            actual.append(type(of: record.event).name)
        }
        let expected = ["Marker"]

        #expect(actual == expected)
    }
}
#endif
