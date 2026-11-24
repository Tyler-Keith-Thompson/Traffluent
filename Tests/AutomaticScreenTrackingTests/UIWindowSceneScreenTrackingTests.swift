// UIKit's view controllers are on iOS, which these tests run on, in the simulator's test host
// (SIMULATOR_TESTS in scripts/modules.py); elsewhere this target builds empty.
//
// Each test awaits its tracker's records in order rather than sleeping: discovery tracks after a
// turn of the main run loop, which awaiting gives it. A test that pins what isn't tracked shows a
// later screen arriving first, where the untracked one would have come before it, after waiting
// for a turn of the run loop with an observer of its own, ordered after discovery's.
#if canImport(UIKit) && !os(watchOS)
import AutomaticScreenTracking
import Events
import SwiftUI
import SwiftUITracking
import Testing
import Trackers
import UIKit
import UIKitTracking

@MainActor
@Suite("UIWindowScene.trackScreensAutomatically", .serialized, .timeLimit(.minutes(1)))
struct UIWindowSceneScreenTrackingTests {
    final class HomeViewController: UIViewController {}

    final class DetailViewController: UIViewController {}

    final class SettingsViewController: UIViewController {}

    struct DetailView: View {
        var id: Int

        var body: some View {
            Text("Detail \(id)")
        }
    }

    struct SettingsView: View {
        var body: some View {
            Text("Settings")
        }
    }

    struct Settings: Hashable {}

    @Observable
    final class Navigation {
        var path = NavigationPath()
    }

    struct StackView: View {
        @Bindable var navigation: Navigation

        var body: some View {
            NavigationStack(path: $navigation.path) {
                Text("Home")
                    .navigationDestination(for: Int.self) { DetailView(id: $0) }
                    .navigationDestination(for: Settings.self) { _ in SettingsView() }
            }
        }
    }

    struct CheckoutStackView: View {
        @Bindable var navigation: Navigation

        var body: some View {
            NavigationStack(path: $navigation.path) {
                Text("Home")
                    .navigationDestination(for: Int.self) { DetailView(id: $0).trackScreen("Checkout") }
                    .navigationDestination(for: Settings.self) { _ in SettingsView() }
            }
        }
    }

    enum Route: Hashable {
        case detail(Int)
        case settings
    }

    @Observable
    final class RouteNavigation {
        var path: [Route] = []
    }

    struct RouteStackView: View {
        @Bindable var navigation: RouteNavigation

        var body: some View {
            NavigationStack(path: $navigation.path) {
                Text("Home")
                    .navigationDestination(for: Route.self) { route in
                        switch route {
                        case .detail(let id): DetailView(id: id)
                        case .settings: SettingsView()
                        }
                    }
            }
        }
    }

    @Test("Pushing a UIKit view controller tracks one ScreenViewed, named after its type")
    func uiKitPush() async throws {
        let tracker = Tracker()
        var records = tracker.records.makeAsyncIterator()
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.traitOverrides.tracker = tracker
        let navigation = UINavigationController(rootViewController: HomeViewController())
        window.rootViewController = navigation
        window.isHidden = false
        defer {
            scene.stopTrackingScreensAutomatically()
            window.isHidden = true
        }
        let expected = [
            ScreenViewed(screen: "HomeViewController"),
            ScreenViewed(screen: "DetailViewController"),
            ScreenViewed(screen: "SettingsViewController"),
        ]

        scene.trackScreensAutomatically()
        var actual: [ScreenViewed] = []
        actual.append(try #require(await records.next()?.event as? ScreenViewed))
        navigation.pushViewController(DetailViewController(), animated: true)
        actual.append(try #require(await records.next()?.event as? ScreenViewed))
        navigation.pushViewController(SettingsViewController(), animated: false)
        actual.append(try #require(await records.next()?.event as? ScreenViewed))

        #expect(actual == expected)
    }

    @Test("Pushing a SwiftUI view in a NavigationStack tracks one ScreenViewed, named after the view; the stack's root takes its host's name")
    func navigationStackPush() async throws {
        let tracker = Tracker()
        var records = tracker.records.makeAsyncIterator()
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.traitOverrides.tracker = tracker
        let navigation = Navigation()
let host = UIHostingController(rootView: StackView(navigation: navigation))
        window.rootViewController = host
        window.isHidden = false
        defer {
            scene.stopTrackingScreensAutomatically()
            window.isHidden = true
        }
        let expected = [
            ScreenViewed(screen: "StackView"),
            ScreenViewed(screen: "DetailView"),
            ScreenViewed(screen: "SettingsView"),
        ]

        scene.trackScreensAutomatically()
        var actual: [ScreenViewed] = []
        actual.append(try #require(await records.next()?.event as? ScreenViewed))
        // Turns of the main run loop until the stack's root is on screen, each past discovery's,
        // which would track the root again now if it tracked the host as well.
        repeat {
            await withCheckedContinuation { (turned: CheckedContinuation<Void, Never>) in
                let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, false, CFIndex.max) { _, _ in turned.resume() }
                CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
            }
        } while host.children.first?.children.first?.viewIfLoaded?.window == nil || host.children.first?.transitionCoordinator != nil
        navigation.path.append(1)
        actual.append(try #require(await records.next()?.event as? ScreenViewed))
        navigation.path.append(Settings())
        actual.append(try #require(await records.next()?.event as? ScreenViewed))

        #expect(actual == expected)
    }

    @Test("A destination that picks its view by the value it presents is named after the value's type and case, without its associated values")
    func destinationByValue() async throws {
        let tracker = Tracker()
        var records = tracker.records.makeAsyncIterator()
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.traitOverrides.tracker = tracker
        let navigation = RouteNavigation()
        window.rootViewController = UIHostingController(rootView: RouteStackView(navigation: navigation))
        window.isHidden = false
        defer {
            scene.stopTrackingScreensAutomatically()
            window.isHidden = true
        }
        let expected = [
            ScreenViewed(screen: "RouteStackView"),
            ScreenViewed(screen: "Route.detail"),
            ScreenViewed(screen: "Route.settings"),
        ]

        scene.trackScreensAutomatically()
        var actual: [ScreenViewed] = []
        actual.append(try #require(await records.next()?.event as? ScreenViewed))
        navigation.path.append(.detail(42))
        actual.append(try #require(await records.next()?.event as? ScreenViewed))
        navigation.path.append(.settings)
        actual.append(try #require(await records.next()?.event as? ScreenViewed))

        #expect(actual == expected)
    }

    @Test("A SwiftUI screen's DiscoveredScreen is of kind swiftUI, and a UIKit one's of kind uiKit")
    func kinds() async throws {
        let tracker = Tracker()
        var records = tracker.records.makeAsyncIterator()
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.traitOverrides.tracker = tracker
        let navigation = UINavigationController(rootViewController: HomeViewController())
        window.rootViewController = navigation
        window.isHidden = false
        defer {
            scene.stopTrackingScreensAutomatically()
            window.isHidden = true
        }
        let expected = [
            ScreenViewed(screen: "uiKit HomeViewController"),
            ScreenViewed(screen: "swiftUI SettingsView"),
        ]

        scene.trackScreensAutomatically { ScreenViewed(screen: "\($0.kind) \($0.name)") }
        var actual: [ScreenViewed] = []
        actual.append(try #require(await records.next()?.event as? ScreenViewed))
        navigation.pushViewController(UIHostingController(rootView: SettingsView().padding()), animated: false)
        actual.append(try #require(await records.next()?.event as? ScreenViewed))

        #expect(actual == expected)
    }

    @Test("A pop tracks the screen it reveals again")
    func pop() async throws {
        let tracker = Tracker()
        var records = tracker.records.makeAsyncIterator()
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.traitOverrides.tracker = tracker
        let navigation = UINavigationController(rootViewController: HomeViewController())
        window.rootViewController = navigation
        window.isHidden = false
        defer {
            scene.stopTrackingScreensAutomatically()
            window.isHidden = true
        }
        let expected = [
            ScreenViewed(screen: "HomeViewController"),
            ScreenViewed(screen: "DetailViewController"),
            ScreenViewed(screen: "HomeViewController"),
        ]

        scene.trackScreensAutomatically()
        var actual: [ScreenViewed] = []
        actual.append(try #require(await records.next()?.event as? ScreenViewed))
        navigation.pushViewController(DetailViewController(), animated: false)
        actual.append(try #require(await records.next()?.event as? ScreenViewed))
        navigation.popViewController(animated: true)
        actual.append(try #require(await records.next()?.event as? ScreenViewed))

        #expect(actual == expected)
    }

    @Test("A presented view controller is a screen, and the one under it isn't tracked again when it is dismissed over it")
    func presentation() async throws {
        let tracker = Tracker()
        var records = tracker.records.makeAsyncIterator()
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.traitOverrides.tracker = tracker
        let navigation = UINavigationController(rootViewController: HomeViewController())
        window.rootViewController = navigation
        window.isHidden = false
        defer {
            scene.stopTrackingScreensAutomatically()
            window.isHidden = true
        }
        let settings = SettingsViewController()
        settings.modalPresentationStyle = .pageSheet
        let expected = [
            ScreenViewed(screen: "HomeViewController"),
            ScreenViewed(screen: "SettingsViewController"),
            ScreenViewed(screen: "DetailViewController"),
        ]

        scene.trackScreensAutomatically()
        var actual: [ScreenViewed] = []
        actual.append(try #require(await records.next()?.event as? ScreenViewed))
        navigation.present(settings, animated: false)
        actual.append(try #require(await records.next()?.event as? ScreenViewed))
        settings.dismiss(animated: false)
        navigation.pushViewController(DetailViewController(), animated: false)
        actual.append(try #require(await records.next()?.event as? ScreenViewed))

        #expect(actual == expected)
    }

    @Test("UIKit's own view controllers, such as a plain UIViewController, aren't screens")
    func frameworkController() async throws {
        let tracker = Tracker()
        var records = tracker.records.makeAsyncIterator()
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.traitOverrides.tracker = tracker
        let plain = UIViewController()
        let navigation = UINavigationController(rootViewController: plain)
        window.rootViewController = navigation
        window.isHidden = false
        defer {
            scene.stopTrackingScreensAutomatically()
            window.isHidden = true
        }
        let expected = ScreenViewed(screen: "DetailViewController")

        scene.trackScreensAutomatically()
        // Turns of the main run loop until the plain controller is on screen, each past discovery's, which runs just before this
        // observer in the same turn.
        repeat {
            await withCheckedContinuation { (turned: CheckedContinuation<Void, Never>) in
                let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, false, CFIndex.max) { _, _ in turned.resume() }
                CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
            }
        } while plain.viewIfLoaded?.window == nil || navigation.transitionCoordinator != nil
        navigation.pushViewController(DetailViewController(), animated: false)
        let actual = try #require(await records.next()?.event as? ScreenViewed)

        #expect(actual == expected)
    }

    @Test("The predicate's event is tracked in place of the default, renaming the screen")
    func rename() async throws {
        let tracker = Tracker()
        var records = tracker.records.makeAsyncIterator()
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.traitOverrides.tracker = tracker
        window.rootViewController = UINavigationController(rootViewController: HomeViewController())
        window.isHidden = false
        defer {
            scene.stopTrackingScreensAutomatically()
            window.isHidden = true
        }
        let expected = ScreenViewed(screen: "Home")

        scene.trackScreensAutomatically { screen in
            ScreenViewed(screen: screen.name == "HomeViewController" ? "Home" : screen.name)
        }
        let actual = try #require(await records.next()?.event as? ScreenViewed)

        #expect(actual == expected)
    }

    @Test("A screen the predicate returns nil for isn't tracked")
    func skip() async throws {
        let tracker = Tracker()
        var records = tracker.records.makeAsyncIterator()
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.traitOverrides.tracker = tracker
        let navigation = UINavigationController(rootViewController: HomeViewController())
        window.rootViewController = navigation
        window.isHidden = false
        defer {
            scene.stopTrackingScreensAutomatically()
            window.isHidden = true
        }
        let expected = [
            ScreenViewed(screen: "HomeViewController"),
            ScreenViewed(screen: "SettingsViewController"),
        ]

        scene.trackScreensAutomatically { screen in
            screen.name == "DetailViewController" ? nil : ScreenViewed(screen: screen.name)
        }
        var actual: [ScreenViewed] = []
        actual.append(try #require(await records.next()?.event as? ScreenViewed))
        let detail = DetailViewController()
        navigation.pushViewController(detail, animated: false)
        // Turns of the main run loop until the detail is on screen, each past discovery's, which runs just before this
        // observer in the same turn.
        repeat {
            await withCheckedContinuation { (turned: CheckedContinuation<Void, Never>) in
                let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, false, CFIndex.max) { _, _ in turned.resume() }
                CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
            }
        } while detail.viewIfLoaded?.window == nil || navigation.transitionCoordinator != nil
        navigation.pushViewController(SettingsViewController(), animated: false)
        actual.append(try #require(await records.next()?.event as? ScreenViewed))

        #expect(actual == expected)
    }

    @Test("Nothing is tracked automatically until trackScreensAutomatically is called")
    func disabledByDefault() async throws {
        let tracker = Tracker()
        var records = tracker.records.makeAsyncIterator()
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.traitOverrides.tracker = tracker
        let navigation = UINavigationController(rootViewController: HomeViewController())
        window.rootViewController = navigation
        window.isHidden = false
        defer {
            scene.stopTrackingScreensAutomatically()
            window.isHidden = true
        }
        let home = try #require(navigation.topViewController)
        // Turns of the main run loop until the home screen is on screen, each past discovery's, which runs just before this
        // observer in the same turn.
        repeat {
            await withCheckedContinuation { (turned: CheckedContinuation<Void, Never>) in
                let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, false, CFIndex.max) { _, _ in turned.resume() }
                CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
            }
        } while home.viewIfLoaded?.window == nil || navigation.transitionCoordinator != nil
        let detail = DetailViewController()
        navigation.pushViewController(detail, animated: false)
        // Turns of the main run loop until the detail is on screen, each past discovery's, which runs just before this
        // observer in the same turn.
        repeat {
            await withCheckedContinuation { (turned: CheckedContinuation<Void, Never>) in
                let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, false, CFIndex.max) { _, _ in turned.resume() }
                CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
            }
        } while detail.viewIfLoaded?.window == nil || navigation.transitionCoordinator != nil
        let expected = ScreenViewed(screen: "DetailViewController")

        scene.trackScreensAutomatically()
        let actual = try #require(await records.next()?.event as? ScreenViewed)

        #expect(actual == expected)
    }

    @Test("With uiKit left out of kinds, UIKit screens aren't tracked but SwiftUI ones are")
    func withoutUIKit() async throws {
        let tracker = Tracker()
        var records = tracker.records.makeAsyncIterator()
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.traitOverrides.tracker = tracker
        let navigation = UINavigationController(rootViewController: HomeViewController())
        window.rootViewController = navigation
        window.isHidden = false
        defer {
            scene.stopTrackingScreensAutomatically()
            window.isHidden = true
        }
        let expected = ScreenViewed(screen: "SettingsView")

        scene.trackScreensAutomatically(kinds: [.swiftUI])
        navigation.pushViewController(UIHostingController(rootView: SettingsView()), animated: true)
        let actual = try #require(await records.next()?.event as? ScreenViewed)

        #expect(actual == expected)
    }

    @Test("With swiftUI left out of kinds, SwiftUI screens aren't tracked but UIKit ones are")
    func withoutSwiftUI() async throws {
        let tracker = Tracker()
        var records = tracker.records.makeAsyncIterator()
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.traitOverrides.tracker = tracker
        let navigation = UINavigationController(rootViewController: UIHostingController(rootView: SettingsView()))
        window.rootViewController = navigation
        window.isHidden = false
        defer {
            scene.stopTrackingScreensAutomatically()
            window.isHidden = true
        }
        let expected = ScreenViewed(screen: "DetailViewController")

        scene.trackScreensAutomatically(kinds: [.uiKit])
        navigation.pushViewController(DetailViewController(), animated: true)
        let actual = try #require(await records.next()?.event as? ScreenViewed)

        #expect(actual == expected)
    }

    @Test("A SwiftUI screen given trackScreen tracks only its own ScreenViewed, not an automatic one too")
    func manualScreenWins() async throws {
        let tracker = Tracker()
        var records = tracker.records.makeAsyncIterator()
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.traitOverrides.tracker = tracker
        let navigation = Navigation()
        let host = UIHostingController(rootView: CheckoutStackView(navigation: navigation))
        window.rootViewController = host
        window.isHidden = false
        defer {
            scene.stopTrackingScreensAutomatically()
            window.isHidden = true
        }
        let expected = [
            ScreenViewed(screen: "CheckoutStackView"),
            ScreenViewed(screen: "Checkout"),
            ScreenViewed(screen: "SettingsView"),
        ]

        scene.trackScreensAutomatically()
        var actual: [ScreenViewed] = []
        actual.append(try #require(await records.next()?.event as? ScreenViewed))
        navigation.path.append(0)
        actual.append(try #require(await records.next()?.event as? ScreenViewed))
        // Turns of the main run loop until the checkout screen is on screen, each past
        // discovery's, which would track it now if trackScreen didn't.
        repeat {
            await withCheckedContinuation { (turned: CheckedContinuation<Void, Never>) in
                let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, false, CFIndex.max) { _, _ in turned.resume() }
                CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
            }
        } while host.children.first?.children.last?.viewIfLoaded?.window == nil || host.children.first?.children.count != 2 || host.children.first?.transitionCoordinator != nil
        navigation.path.append(Settings())
        actual.append(try #require(await records.next()?.event as? ScreenViewed))

        #expect(actual == expected)
    }

    @Test("Each screen view goes through the tracker its screen's traits hold, so two windows keep theirs apart")
    func screenTrackers() async throws {
        let homeTracker = Tracker()
        let settingsTracker = Tracker()
        var homeRecords = homeTracker.records.makeAsyncIterator()
        var settingsRecords = settingsTracker.records.makeAsyncIterator()
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let homeWindow = UIWindow(windowScene: scene)
        homeWindow.traitOverrides.tracker = homeTracker
        homeWindow.rootViewController = HomeViewController()
        let settingsWindow = UIWindow(windowScene: scene)
        settingsWindow.traitOverrides.tracker = settingsTracker
        settingsWindow.rootViewController = SettingsViewController()
        homeWindow.isHidden = false
        settingsWindow.isHidden = false
        defer {
            scene.stopTrackingScreensAutomatically()
            homeWindow.isHidden = true
            settingsWindow.isHidden = true
        }
        let expectedHome = [ScreenViewed(screen: "HomeViewController")]
        let expectedSettings = [ScreenViewed(screen: "SettingsViewController")]

        scene.trackScreensAutomatically()
        let firstHome = try #require(await homeRecords.next()?.event as? ScreenViewed)
        let firstSettings = try #require(await settingsRecords.next()?.event as? ScreenViewed)
        scene.stopTrackingScreensAutomatically()
        await homeTracker.finish()
        await settingsTracker.finish()

        var actualHome = [firstHome]
        while let record = await homeRecords.next() {
            actualHome.append(try #require(record.event as? ScreenViewed))
        }
        var actualSettings = [firstSettings]
        while let record = await settingsRecords.next() {
            actualSettings.append(try #require(record.event as? ScreenViewed))
        }
        #expect(actualHome == expectedHome)
        #expect(actualSettings == expectedSettings)
    }

    @Test("A hidden window's screens aren't tracked")
    func hiddenWindow() async throws {
        let tracker = Tracker()
        var records = tracker.records.makeAsyncIterator()
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.traitOverrides.tracker = tracker
        let navigation = UINavigationController(rootViewController: HomeViewController())
        window.rootViewController = navigation
        let hiddenWindow = UIWindow(windowScene: scene)
        hiddenWindow.traitOverrides.tracker = tracker
        hiddenWindow.rootViewController = SettingsViewController()
        hiddenWindow.isHidden = false
        window.isHidden = false
        defer {
            scene.stopTrackingScreensAutomatically()
            window.isHidden = true
        }
        // Laid out in a window, then hidden: its controller's view stays in it.
        hiddenWindow.layoutIfNeeded()
        hiddenWindow.isHidden = true
        let expected = [
            ScreenViewed(screen: "HomeViewController"),
            ScreenViewed(screen: "DetailViewController"),
        ]

        scene.trackScreensAutomatically()
        var actual: [ScreenViewed] = []
        actual.append(try #require(await records.next()?.event as? ScreenViewed))
        navigation.pushViewController(DetailViewController(), animated: false)
        actual.append(try #require(await records.next()?.event as? ScreenViewed))

        #expect(actual == expected)
    }

    @Test("A screen view's call site is where trackScreensAutomatically is called")
    func callSite() async throws {
        let tracker = Tracker()
        var records = tracker.records.makeAsyncIterator()
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.traitOverrides.tracker = tracker
        window.rootViewController = HomeViewController()
        window.isHidden = false
        defer {
            scene.stopTrackingScreensAutomatically()
            window.isHidden = true
        }
        let expectedLine = #line + 3
        let expectedFileID = #fileID

        scene.trackScreensAutomatically()
        let actual = try #require(await records.next()?.sourceLocation)

        #expect(actual.line == expectedLine)
        #expect(actual.fileID == expectedFileID)
        #expect(actual.function == "callSite()")
    }

    @Test("After stopTrackingScreensAutomatically, screens aren't tracked")
    func stop() async throws {
        let tracker = Tracker()
        var records = tracker.records.makeAsyncIterator()
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.traitOverrides.tracker = tracker
        let navigation = UINavigationController(rootViewController: HomeViewController())
        window.rootViewController = navigation
        window.isHidden = false
        defer {
            scene.stopTrackingScreensAutomatically()
            window.isHidden = true
        }
        let expected = [
            ScreenViewed(screen: "HomeViewController"),
            ScreenViewed(screen: "SettingsViewController"),
        ]

        scene.trackScreensAutomatically()
        var actual: [ScreenViewed] = []
        actual.append(try #require(await records.next()?.event as? ScreenViewed))
        scene.stopTrackingScreensAutomatically()
        let detail = DetailViewController()
        navigation.pushViewController(detail, animated: false)
        // Turns of the main run loop until the detail is on screen, each past discovery's, which runs just before this
        // observer in the same turn.
        repeat {
            await withCheckedContinuation { (turned: CheckedContinuation<Void, Never>) in
                let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, false, CFIndex.max) { _, _ in turned.resume() }
                CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
            }
        } while detail.viewIfLoaded?.window == nil || navigation.transitionCoordinator != nil
        let settings = SettingsViewController()
        navigation.pushViewController(settings, animated: false)
        // Turns of the main run loop until the settings are on screen, each past discovery's, which runs just before this
        // observer in the same turn.
        repeat {
            await withCheckedContinuation { (turned: CheckedContinuation<Void, Never>) in
                let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, false, CFIndex.max) { _, _ in turned.resume() }
                CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
            }
        } while settings.viewIfLoaded?.window == nil || navigation.transitionCoordinator != nil
        scene.trackScreensAutomatically()
        actual.append(try #require(await records.next()?.event as? ScreenViewed))

        #expect(actual == expected)
    }

    @Test("Calling trackScreensAutomatically again replaces the earlier call's predicate and kinds")
    func replace() async throws {
        let tracker = Tracker()
        var records = tracker.records.makeAsyncIterator()
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.traitOverrides.tracker = tracker
        let navigation = UINavigationController(rootViewController: HomeViewController())
        window.rootViewController = navigation
        window.isHidden = false
        defer {
            scene.stopTrackingScreensAutomatically()
            window.isHidden = true
        }
        let expected = [
            ScreenViewed(screen: "first HomeViewController"),
            ScreenViewed(screen: "second DetailViewController"),
        ]

        scene.trackScreensAutomatically { ScreenViewed(screen: "first \($0.name)") }
        var actual: [ScreenViewed] = []
        actual.append(try #require(await records.next()?.event as? ScreenViewed))
        navigation.pushViewController(DetailViewController(), animated: false)
        scene.trackScreensAutomatically { ScreenViewed(screen: "second \($0.name)") }
        actual.append(try #require(await records.next()?.event as? ScreenViewed))

        #expect(actual == expected)
    }
}
#endif
