// UIKit's custom traits are on iOS, iPadOS, tvOS, visionOS and Mac Catalyst; watchOS's UIKit has
// none. Elsewhere this module builds empty, so the package still does.
#if canImport(UIKit) && !os(watchOS)
public import Trackers
public import UIKit

/// The UIKit trait holding the tracker that views and view controllers track their events through.
///
/// Set it once, where a scene connects, and every view controller and view in the scene's windows
/// inherits it, as SwiftUI views inherit their environment:
///
/// ```swift
/// func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
///     guard let windowScene = scene as? UIWindowScene else { return }
///     windowScene.traitOverrides.tracker = tracker
/// }
/// ```
///
/// Read it in any view or view controller below with `traitCollection.tracker`, such as in an
/// action:
///
/// ```swift
/// @objc func checkOut(_ sender: UIButton) {
///     sender.traitCollection.tracker.track(CheckoutStarted(cartSize: 3))
/// }
/// ```
///
/// A view controller or view sets its own with its `traitOverrides`, for itself and everything
/// below it, such as a tracker enriched with a screen's name. Each scene keeps its own, so an app
/// with two windows can track each through a tracker of its own. SwiftUI views hosted in UIKit
/// read the same tracker from `@Environment(\.tracker)`, and UIKit views hosted in SwiftUI read
/// the environment's.
///
/// Until a tracker is set, it tracks as `Tracker.current` does with nothing bound: through the
/// tracker `Tracker.bootstrap(_:)` made the process's default, looked up as each event is tracked,
/// so a view that reads it before the app bootstraps still reaches it. With none bootstrapped it
/// drops each event, logging the first from each call site at warning level, so a scene whose
/// tracker was forgotten shows up in the logs. In an Xcode preview it is `Tracker.noOp` instead,
/// which drops every event quietly.
public struct TrackerTrait: UITraitDefinition {
    /// The tracker of a trait collection no tracker was set in: one that tracks through the
    /// bootstrapped tracker, looked up as each event is tracked, and warns of each call site's
    /// first drop when none is bootstrapped (`Tracker.noOp` in an Xcode preview).
    public static let defaultValue: Tracker = .viewDefault
}

extension UITraitCollection {
    /// The tracker the views and view controllers with these traits track their events through:
    /// the ``TrackerTrait``.
    public var tracker: Tracker {
        self[TrackerTrait.self]
    }
}

extension UIMutableTraits {
    /// The tracker the views and view controllers with these traits track their events through:
    /// the ``TrackerTrait``.
    ///
    /// Set it on a window scene's, a view controller's or a view's `traitOverrides`, and everything
    /// below inherits it.
    public var tracker: Tracker {
        get { self[TrackerTrait.self] }
        set { self[TrackerTrait.self] = newValue }
    }
}
#endif
