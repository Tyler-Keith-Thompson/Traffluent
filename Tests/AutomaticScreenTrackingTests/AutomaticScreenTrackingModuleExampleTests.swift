// The window scene example of AutomaticScreenTracking's landing article
// (Sources/AutomaticScreenTracking/AutomaticScreenTracking.docc/AutomaticScreenTracking.md),
// verbatim. TraffluentTests runs on the Mac and Linux, where UIKit isn't, so it runs here, in the
// simulator. An extension of the suite the other tests are in, so it runs serialized with them:
// they share the test host's one window scene. Its HomeViewController is that suite's.
#if canImport(UIKit) && !os(watchOS)
import AutomaticScreenTracking
import SwiftUITracking
import Testing
import Trackers
import UIKit
import UIKitTracking

extension UIWindowSceneScreenTrackingTests {
    @Test("AutomaticScreenTracking module example: window scene")
    func windowSceneExample() async throws {
        let tracker = Tracker()
        var records = tracker.records.makeAsyncIterator()
        let windowScene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UINavigationController(rootViewController: HomeViewController())
        window.isHidden = false
        // The test host's own windows keep out of the scene's tracker.
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
            screen.name == "DebugMenuViewController" ? nil : ScreenViewed(screen: screen.name)
        }
        let actual = try #require(await records.next()?.event as? ScreenViewed)

        #expect(actual == ScreenViewed(screen: "HomeViewController"))
    }
}
#endif
