// What discovery reads of a view controller, in UIKit's and AppKit's terms, so that ScreenDiscovery
// is written once for both. Public API alone: no private selectors or classes.
#if canImport(SwiftUI) && canImport(UIKit) && !os(watchOS)
import SwiftUI
import SwiftUITracking
import Trackers
import UIKit
import UIKitTracking

typealias ViewController = UIViewController

/// A hosting controller of any root view, whose root view discovery names the screen after.
@MainActor
protocol HostingController {
    /// The SwiftUI view the controller shows.
    var hostedRootView: Any { get }
}

// Its subclasses too, such as the controller a `NavigationStack` pushes each view in.
extension UIHostingController: HostingController {
    var hostedRootView: Any { rootView }
}

extension DiscoveredScreen.Kind {
    /// The kind of a view controller that isn't a hosting controller.
    static var platformViewController: Self { .uiKit }
}

extension UIViewController {
    /// Whether the controller's view is in a window.
    var isOnScreen: Bool {
        viewIfLoaded?.window != nil
    }

    /// The controller this one presents, unless an ancestor does: then the ancestor lists it.
    var presentedScreens: [UIViewController] {
        guard let presentedViewController, presentedViewController.presentingViewController === self else { return [] }
        return [presentedViewController]
    }

    /// Whether a push, pop, presentation or dismissal involving this controller is running.
    var isTransitioning: Bool {
        transitionCoordinator != nil
    }

    /// Whether a view in the controller's view's hierarchy is the marker `trackScreen(_:)` leaves.
    var hasTrackedScreenMarker: Bool {
        guard let view = viewIfLoaded else { return false }
        var views = [view]
        while let next = views.popLast() {
            if next is TrackedScreenMarkerView {
                return true
            }
            views += next.subviews
        }
        return false
    }

    /// The tracker the controller's traits hold: its scene's, or one set on it or above it.
    var screenTracker: Tracker {
        traitCollection.tracker
    }
}
#elseif canImport(SwiftUI) && canImport(AppKit)
import AppKit
import AppKitTracking
import SwiftUI
import SwiftUITracking
import Trackers

typealias ViewController = NSViewController

/// A hosting controller of any root view, whose root view discovery names the screen after.
@MainActor
protocol HostingController {
    /// The SwiftUI view the controller shows.
    var hostedRootView: Any { get }
}

extension NSHostingController: HostingController {
    var hostedRootView: Any { rootView }
}

extension DiscoveredScreen.Kind {
    /// The kind of a view controller that isn't a hosting controller.
    static var platformViewController: Self { .appKit }
}

extension NSViewController {
    /// Whether the controller's view is in a window on screen, and not hidden.
    var isOnScreen: Bool {
        isViewLoaded && view.window?.isVisible == true && !view.isHiddenOrHasHiddenAncestor
    }

    /// The controllers this one presents, as sheets, modal windows or popovers.
    var presentedScreens: [NSViewController] {
        presentedViewControllers ?? []
    }

    /// Always `false`: AppKit's transitions (`transition(from:to:options:)`) swap views at once.
    var isTransitioning: Bool {
        false
    }

    /// Whether a view in the controller's view's hierarchy is the marker `trackScreen(_:)` leaves.
    var hasTrackedScreenMarker: Bool {
        guard isViewLoaded else { return false }
        var views = [view]
        while let next = views.popLast() {
            if next is TrackedScreenMarkerView {
                return true
            }
            views += next.subviews
        }
        return false
    }

    /// The tracker the controller's view finds up its responder chain.
    var screenTracker: Tracker {
        view.tracker
    }
}
#endif
