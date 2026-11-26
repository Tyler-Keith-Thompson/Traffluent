// The example of UIKitTracking's landing article
// (Sources/UIKitTracking/UIKitTracking.docc/UIKitTracking.md), verbatim, so the article cannot drift
// from the code. TraffluentTests runs on the Mac and Linux, where UIKit isn't, so it runs here, in
// the simulator, serialized with the other suites that use the test host's window scene.
#if canImport(UIKit) && !os(watchOS)
import Events
import Testing
import Trackers
import UIKit
import UIKitTracking

extension SerializedSuites {
    @MainActor
    @Suite("UIKitTracking module examples", .serialized, .timeLimit(.minutes(1)))
    struct UIKitTrackingModuleExamplesTests {
        struct ShareTapped: Event {}

        struct CheckoutStarted: Event {
            var cartSize: Int
        }

        final class CartViewController: UIViewController {
            let share = UIButton(configuration: .filled())
            let checkOut = UIButton(configuration: .filled())

            override func viewDidLoad() {
                super.viewDidLoad()
                share.track(ShareTapped())  // through the tracker the button's traits hold when it is tapped
                checkOut.addTarget(self, action: #selector(checkOut(_:)), for: .primaryActionTriggered)
                view.addSubview(share)
                view.addSubview(checkOut)
            }

            @objc func checkOut(_ sender: UIButton) {
                sender.traitCollection.tracker.track(CheckoutStarted(cartSize: 3))
            }
        }

        @Test("Overview")
        func overview() async throws {
            let tracker = Tracker()
            let windowScene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
            defer { windowScene.traitOverrides.remove(TrackerTrait.self) }

            // In the scene delegate's scene(_:willConnectTo:options:):
            windowScene.traitOverrides.tracker = tracker

            let window = UIWindow(windowScene: windowScene)
            let controller = CartViewController()
            window.rootViewController = controller
            window.isHidden = false
            defer { window.isHidden = true }
            window.layoutIfNeeded()
            controller.share.sendActions(for: .primaryActionTriggered)
            controller.checkOut.sendActions(for: .primaryActionTriggered)
            await tracker.finish()
            var actual: [String] = []
            for await record in tracker.records {
                actual.append(type(of: record.event).name)
            }
            let expected = ["ShareTapped", "CheckoutStarted"]

            #expect(actual == expected)
        }
    }
}
#endif
