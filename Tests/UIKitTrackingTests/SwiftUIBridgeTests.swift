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

extension SerializedSuites {
    @MainActor
    @Suite("SwiftUI's environment and UIKit's traits share the tracker", .serialized, .timeLimit(.minutes(1)))
    struct SwiftUIBridgeTests {
        struct CartOpened: Event, Equatable {}

        struct HomeOpened: Event, Equatable {}

        struct ShareTapped: Event, Equatable {}

        struct ShareButton: UIViewRepresentable {
            func makeUIView(context: Context) -> UIButton {
                let button = UIButton(type: .system)
                button.track(ShareTapped())
                return button
            }

            func updateUIView(_ uiView: UIButton, context: Context) {}
        }

        @Observable
        final class Navigation {
            var path: [Int] = []
        }

        struct OpenedStack: View {
            @Bindable var navigation: Navigation

            var body: some View {
                NavigationStack(path: $navigation.path) {
                    Text("Home")
                        .navigationDestination(for: Int.self) { _ in
                            Text("Cart").trackOnAppear(CartOpened())
                        }
                }
            }
        }

        struct ScreenStack: View {
            @Bindable var navigation: Navigation

            var body: some View {
                NavigationStack(path: $navigation.path) {
                    Text("Home")
                        .navigationDestination(for: Int.self) { _ in
                            Text("Checkout").trackScreen("Checkout")
                        }
                }
            }
        }

        @Test("A view a NavigationStack pushes tracks trackOnAppear's event through the tracker its window's traits hold")
        func navigationStackDestination() async throws {
            let tracker = Tracker()
            var records = tracker.records.makeAsyncIterator()
            let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
            let window = UIWindow(windowScene: scene)
            window.traitOverrides.tracker = tracker
            let navigation = Navigation()
            window.rootViewController = UIHostingController(rootView: OpenedStack(navigation: navigation))
            window.isHidden = false
            defer { window.isHidden = true }
            let expected = CartOpened()

            navigation.path.append(1)
            // The destination appears before its hosting controller's traits hold the window's
            // tracker, and tracks once they do: awaited, with the suite's time limit.
            let actual = try #require(await records.next()?.event as? CartOpened)

            #expect(actual == expected)
        }

        @Test("A screen a NavigationStack pushes tracks ScreenViewed through the tracker its window's traits hold, carrying its ScreenKey")
        func navigationStackScreen() async throws {
            let tracker = Tracker()
            var records = tracker.records.makeAsyncIterator()
            let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
            let window = UIWindow(windowScene: scene)
            window.traitOverrides.tracker = tracker
            let navigation = Navigation()
            window.rootViewController = UIHostingController(rootView: ScreenStack(navigation: navigation))
            window.isHidden = false
            defer { window.isHidden = true }
            let expectedEvent = ScreenViewed(screen: "Checkout")
            let expectedScreen: String? = "Checkout"

            navigation.path.append(1)
            let record = try #require(await records.next())

            let actualEvent = try #require(record.event as? ScreenViewed)
            #expect(actualEvent == expectedEvent)
            #expect(record.context[ScreenKey.self] == expectedScreen)
        }

        @Observable
        final class CoveredNavigation {
            var path: [Int] = []
            var isRootCovered = false
        }

        struct CoveredStack: View {
            @Bindable var navigation: CoveredNavigation

            var body: some View {
                NavigationStack(path: $navigation.path) {
                    Text("Home")
                        .trackOnAppear(HomeOpened())
                        .onDisappear { navigation.isRootCovered = true }
                        .navigationDestination(for: Int.self) { _ in
                            Text("Cart").trackOnAppear(CartOpened())
                        }
                }
            }
        }

        @Test("A stack's root covered by a pushed view before a tracker reaches them tracks nothing once one does; the pushed view does")
        func coveredBeforeTracker() async throws {
            let tracker = Tracker()
            var records = tracker.records.makeAsyncIterator()
            let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
            let window = UIWindow(windowScene: scene)
            let navigation = CoveredNavigation()
            let host = UIHostingController(rootView: CoveredStack(navigation: navigation))
            window.rootViewController = host
            window.isHidden = false
            defer { window.isHidden = true }
            // Turns of the main run loop until the stack's root is on screen.
            repeat {
                await withCheckedContinuation { (turned: CheckedContinuation<Void, Never>) in
                    let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, false, CFIndex.max) { _, _ in turned.resume() }
                    CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
                }
            } while host.children.first?.children.first?.viewIfLoaded?.window == nil
            navigation.path.append(1)
            // Turns until the pushed view is on screen and SwiftUI has told the root it disappeared.
            repeat {
                await withCheckedContinuation { (turned: CheckedContinuation<Void, Never>) in
                    let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, false, CFIndex.max) { _, _ in turned.resume() }
                    CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
                }
            } while !navigation.isRootCovered || host.children.first?.children.last?.viewIfLoaded?.window == nil
            let expected = [CartOpened.name]

            window.traitOverrides.tracker = tracker
            var actual = [type(of: try #require(await records.next()?.event)).name]
            await tracker.finish()
            while let record = await records.next() {
                actual.append(type(of: record.event).name)
            }

            #expect(actual == expected)
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
}
#endif
