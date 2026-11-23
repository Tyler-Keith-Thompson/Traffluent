// The README's automatic screen views example, verbatim. TraffluentTests runs on the Mac and Linux,
// where UIKit isn't, so it runs here, in the simulator. An extension of the suite the other tests
// are in, so it runs serialized with them: they share the test host's one window scene.
#if canImport(UIKit) && !os(watchOS)
import AutomaticScreenTracking
import SwiftUI
import SwiftUITracking
import Testing
import Trackers
import UIKit
import UIKitTracking

extension UIWindowSceneScreenTrackingTests {
    final class DebugMenuViewController: UIViewController {}

    struct CheckoutView: View {
        var body: some View {
            Text("Checkout")
        }
    }

    @Test("README example: automatic screen views")
    func readmeExample() async throws {
        let tracker = Tracker()
        var records = tracker.records.makeAsyncIterator()
        let windowScene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: windowScene)
        let navigation = UINavigationController(rootViewController: HomeViewController())
        window.rootViewController = navigation
        window.isHidden = false
        // The test host's own window keeps out of the scene's tracker.
        let hostWindows = windowScene.windows.filter { $0 !== window }
        for hostWindow in hostWindows {
            hostWindow.traitOverrides.tracker = .noOp
        }
        defer {
            windowScene.stopTrackingScreensAutomatically()
            windowScene.traitOverrides.remove(TrackerTrait.self)
            for hostWindow in hostWindows {
                hostWindow.traitOverrides.remove(TrackerTrait.self)
            }
            window.isHidden = true
        }

        // In the scene delegate's scene(_:willConnectTo:options:), beside the scene's tracker:
        windowScene.traitOverrides.tracker = tracker
        windowScene.trackScreensAutomatically { screen in
            switch screen.name {
            case "DebugMenuViewController": nil  // not tracked
            case "CheckoutView": ScreenViewed(screen: "Checkout")
            default: ScreenViewed(screen: screen.name)
            }
        }

        var screens: [String] = []
        screens.append(try #require(await records.next()?.event as? ScreenViewed).screen)
        let debugMenu = DebugMenuViewController()
        navigation.pushViewController(debugMenu, animated: false)
        // Turns of the main run loop until the debug menu is on screen, each past discovery's.
        repeat {
            await withCheckedContinuation { (turned: CheckedContinuation<Void, Never>) in
                let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, false, CFIndex.max) { _, _ in turned.resume() }
                CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
            }
        } while debugMenu.viewIfLoaded?.window == nil || navigation.transitionCoordinator != nil
        navigation.pushViewController(UIHostingController(rootView: CheckoutView()), animated: true)
        screens.append(try #require(await records.next()?.event as? ScreenViewed).screen)

        #expect(screens == ["HomeViewController", "Checkout"])
    }
}
#endif
