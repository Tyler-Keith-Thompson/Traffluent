#if canImport(SwiftUI) && ((canImport(UIKit) && !os(watchOS)) || canImport(AppKit))
import CoreFoundation
import Foundation
import Events
import SwiftUITracking
import Trackers

/// Watches the view controllers of one window scene or window, and tracks a screen view for each
/// screen that appears in it.
///
/// A screen is a view controller on screen with no child on screen: the controller a navigation
/// controller shows, a tab bar controller's selected one, one presented. Containers frame screens
/// rather than being them. After each turn of the main run loop, once the turn's layout is done,
/// it lists the screens, and tracks each that wasn't on screen the turn before: one pushed or
/// presented, or one revealed again by a pop or a dismissal.
// The trigger is a run-loop observer, the one way to learn that a view controller appeared using
// public API alone and nothing global. Rejected:
// - Swizzling `viewDidAppear(_:)` (what other analytics SDKs do): it changes every view controller
//   in the process, every scene's alike, and the charter rules it out (N2).
// - A `UINavigationControllerDelegate` forwarding to the app's own: it sees only navigation
//   controllers the app makes, and would replace the delegate SwiftUI's `NavigationStack` sets on
//   its own.
// - A container view controller the app wraps its root in: appearance callbacks reach it only for
//   its own view, not for pushes deeper down.
// - KVO on `viewControllers` or `presentedViewController`: neither is documented as observable.
// - A timer or display link: work on every frame, whether anything changed or not.
// The observer does its work only when the main thread is about to sleep, after the events and
// layout of a turn, and its walk visits only the controllers on screen.
@MainActor
final class ScreenDiscovery {
    private let kinds: Set<DiscoveredScreen.Kind>
    private let screenViewed: @MainActor (DiscoveredScreen) -> ScreenViewed?
    private let callSite: SourceLocation
    private let roots: @MainActor () -> [ViewController]
    private var observer: CFRunLoopObserver?
    /// The screens on screen at the last turn, held weakly: a screen that has gone is not kept
    /// alive until the next turn.
    private var shown: [WeakViewController] = []

    /// Discovery of the screens below `roots`.
    ///
    /// - Parameters:
    ///   - kinds: The kinds of screen to track.
    ///   - screenViewed: The event for a discovered screen, or `nil` to skip it.
    ///   - callSite: The call site each screen view records.
    ///   - previous: The discovery this one replaces, whose screens on screen this one doesn't
    ///     track again; `nil` to track every screen on screen at the next turn.
    ///   - roots: The view controllers to look below: a window scene's windows' root view
    ///     controllers, or a window's content view controller.
    init(
        kinds: Set<DiscoveredScreen.Kind>,
        screenViewed: @escaping @MainActor (DiscoveredScreen) -> ScreenViewed?,
        callSite: SourceLocation,
        replacing previous: ScreenDiscovery?,
        roots: @escaping @MainActor () -> [ViewController]
    ) {
        shown = previous?.shown ?? []
        self.kinds = kinds
        self.screenViewed = screenViewed
        self.callSite = callSite
        self.roots = roots
        // After the run loop's observers that UIKit and AppKit lay out and commit with, so a
        // screen that appeared this turn has drawn its views; one below the largest order, so an
        // observer can still follow it. Weak, so that the run loop, which keeps the observer,
        // doesn't keep discovery alive.
        let observer = CFRunLoopObserverCreateWithHandler(kCFAllocatorDefault, CFRunLoopActivity.beforeWaiting.rawValue, true, CFIndex.max - 1) { [weak self] _, _ in
            // The main run loop's observers run on the main thread.
            MainActor.assumeIsolated {
                self?.discover()
            }
        }
        // Common modes, so a screen appearing while a modal session or a scroll runs the loop in
        // another mode is still found.
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        self.observer = observer
    }

    isolated deinit {
        if let observer {
            CFRunLoopObserverInvalidate(observer)
        }
    }

    /// Lists the screens on screen now, and tracks a screen view for each that wasn't at the last
    /// turn. Does nothing while a transition runs, so a pop the user cancels halfway tracks
    /// nothing; the turn after it ends looks again.
    func discover() {
        var screens: [ViewController] = []
        for root in roots() {
            guard root.collectScreens(into: &screens) else { return }
        }
        let previous = shown
        let appeared = screens.filter { screen in !previous.contains { $0.controller === screen } }
        shown = screens.map(WeakViewController.init)
        for screen in appeared {
            // A hosting controller's screen is a `NavigationStack`'s root, named after the hosting
            // controller around the stack, which was itself the screen until the stack's own
            // controllers appeared, a turn or more later: the same screen, tracked once.
            let replacesItsHost = screen.namingHost.map { host in
                host !== screen && previous.contains { $0.controller === host }
            } ?? false
            if !replacesItsHost {
                track(screen)
            }
        }
    }

    /// Tracks a view of `screen` through its own tracker, unless its kind is off, it is one of
    /// UIKit's or AppKit's own, `trackScreen(_:)` tracks it, or the predicate skips it.
    private func track(_ screen: ViewController) {
        guard !screen.isFrameworkController,
              kinds.contains(screen.screenKind),
              !screen.hasTrackedScreenMarker,
              let event = screenViewed(DiscoveredScreen(name: screen.screenName, kind: screen.screenKind))
        else { return }
        screen.screenTracker.track(event, file: callSite.file, fileID: callSite.fileID, function: callSite.function, line: callSite.line, column: callSite.column)
    }
}

extension ScreenDiscovery {
    /// The key a window scene or window keeps its discovery under, as an associated object: the
    /// address of an object no other association uses.
    static var associationKey: UnsafeRawPointer {
        UnsafeRawPointer(Unmanaged.passUnretained(AssociationKey.instance).toOpaque())
    }
}

/// The object whose address is ``ScreenDiscovery/associationKey``: a constant, holding nothing.
private final class AssociationKey: Sendable {
    static let instance = AssociationKey()
}

/// A view controller, held weakly.
struct WeakViewController {
    weak var controller: ViewController?
}

extension ViewController {
    /// Adds the screens on screen at or below this controller to `screens`, in order: the
    /// controller itself if none of its children is on screen, else theirs; then those of the
    /// controllers it presents, which may be on screen when it isn't.
    ///
    /// - Returns: `false` if a transition is running here, when the screens can't be told yet.
    fileprivate func collectScreens(into screens: inout [ViewController]) -> Bool {
        guard !isTransitioning else { return false }
        if isOnScreen {
            let visibleChildren = children.filter(\.isOnScreen)
            if visibleChildren.isEmpty {
                screens.append(self)
            }
            for child in visibleChildren {
                guard child.collectScreens(into: &screens) else { return false }
            }
        }
        for presented in presentedScreens {
            guard presented.collectScreens(into: &screens) else { return false }
        }
        return true
    }

    /// The name of the screen this controller draws: for a hosting controller, its root view's
    /// screen name, or failing that the nearest enclosing hosting controller's, as for a
    /// `NavigationStack`'s root, whose type SwiftUI erases; otherwise its own type's name.
    fileprivate var screenName: String {
        if let namingHost, let hosting = namingHost as? HostingController, let name = TypeName.screenName(ofView: hosting.hostedRootView) {
            return name
        }
        return String(describing: type(of: self))
    }

    /// The hosting controller whose root view names this controller's screen: for a hosting
    /// controller, itself or the nearest enclosing one whose root view has a screen name; `nil`
    /// for other controllers.
    fileprivate var namingHost: ViewController? {
        guard self is HostingController else { return nil }
        return sequence(first: self, next: \.parent)
            .first { ($0 as? HostingController).flatMap { TypeName.screenName(ofView: $0.hostedRootView) } != nil }
    }

    /// What draws this controller's screen.
    fileprivate var screenKind: DiscoveredScreen.Kind {
        self is HostingController ? .swiftUI : .platformViewController
    }

    /// Whether this controller is one of the UI framework's own, such as an alert or the
    /// keyboard's, rather than the app's or SwiftUI's.
    fileprivate var isFrameworkController: Bool {
        Bundle(for: type(of: self)) == Bundle(for: ViewController.self)
    }
}
#endif
