// The README's UIKit example, verbatim. TraffluentTests runs on the Mac and Linux, where UIKit
// isn't, so it runs here, in the simulator.
#if canImport(UIKit) && !os(watchOS)
import Events
import Testing
import Trackers
import UIKit
import UIKitTracking

extension SerializedSuites {
    @MainActor
    @Suite("README examples: UIKit", .serialized, .timeLimit(.minutes(1)))
    struct READMEUIKitExampleTests {
        struct SignedUp: Event {
            var plan: String
        }

        struct ShareTapped: Event {}

        final class CheckoutViewController: UIViewController {
            let share = UIButton(configuration: .filled())

            override func viewDidLoad() {
                super.viewDidLoad()
                share.track(ShareTapped())  // through the tracker the button's traits hold when it is tapped
                share.addTarget(self, action: #selector(signUp(_:)), for: .primaryActionTriggered)
                view.addSubview(share)
            }

            @objc func signUp(_ sender: UIButton) {
                sender.traitCollection.tracker.track(SignedUp(plan: "pro"))
            }
        }

        @Test("UIKit")
        func uiKit() async throws {
            let tracker = Tracker()
            let windowScene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
            defer { windowScene.traitOverrides.remove(TrackerTrait.self) }

            // In the scene delegate's scene(_:willConnectTo:options:):
            windowScene.traitOverrides.tracker = tracker

            let window = UIWindow(windowScene: windowScene)
            let controller = CheckoutViewController()
            window.rootViewController = controller
            window.isHidden = false
            defer { window.isHidden = true }
            window.layoutIfNeeded()
            controller.share.sendActions(for: .primaryActionTriggered)
            await tracker.finish()
            var names: Set<String> = []
            for await record in tracker.records {
                names.insert(type(of: record.event).name)
            }

            #expect(names == ["ShareTapped", "SignedUp"])
        }
    }
}
#endif
