// The bridge between SwiftUI's environment and UIKit's traits is SwiftUITracking's, but only UIKit
// platforms have it, so its tests run here, in the simulator.
#if canImport(UIKit) && !os(watchOS)
import Events
import SwiftUI
import SwiftUITracking
import Testing
import Trackers
import UIKit
import UIKitTracking

@MainActor
@Suite("SwiftUI's environment and UIKit's traits share the tracker", .serialized, .timeLimit(.minutes(1)))
struct SwiftUIBridgeTests {
    struct CartOpened: Event, Equatable {}

    struct ShareTapped: Event, Equatable {}

    struct ShareButton: UIViewRepresentable {
        func makeUIView(context: Context) -> UIButton {
            let button = UIButton(type: .system)
            button.track(ShareTapped())
            return button
        }

        func updateUIView(_ uiView: UIButton, context: Context) {}
    }

    @Test("A SwiftUI view hosted in UIKit tracks through the tracker its view controller's traits hold")
    func swiftUIInUIKit() async throws {
        let tracker = Tracker()
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: Text("Cart").trackOnAppear(CartOpened()))
        host.traitOverrides.tracker = tracker
        window.rootViewController = host
        let expected = [CartOpened()]

        window.isHidden = false
        defer { window.isHidden = true }
        window.layoutIfNeeded()
        await tracker.finish()

        var actual: [CartOpened] = []
        for await record in tracker.records {
            actual.append(try #require(record.event as? CartOpened))
        }
        #expect(actual == expected)
    }

    @Test("A UIKit control hosted in SwiftUI tracks through the environment's tracker")
    func uiKitInSwiftUI() async throws {
        let tracker = Tracker()
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: ShareButton().tracker(tracker))
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }
        window.layoutIfNeeded()
        var views: [UIView] = [host.view]
        var found: UIButton?
        while found == nil, !views.isEmpty {
            let view = views.removeFirst()
            found = view as? UIButton
            views += view.subviews
        }
        let button = try #require(found)
        let expected = [ShareTapped()]

        button.sendActions(for: .primaryActionTriggered)
        await tracker.finish()

        var actual: [ShareTapped] = []
        for await record in tracker.records {
            actual.append(try #require(record.event as? ShareTapped))
        }
        #expect(actual == expected)
    }
}
#endif
