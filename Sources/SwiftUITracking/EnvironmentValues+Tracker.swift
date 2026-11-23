// SwiftUI is on Apple platforms alone; elsewhere this module builds empty, so the package still
// does.
#if canImport(SwiftUI)
public import SwiftUI
public import Trackers
#if canImport(UIKit) && !os(watchOS)
import UIKit
import UIKitTracking
#endif

extension EnvironmentValues {
    /// The tracker the views in this environment track their events through.
    ///
    /// Set it once, at the root of the app's views, with `tracker(_:)`, and read it in any view
    /// below with `@Environment(\.tracker)`:
    ///
    /// ```swift
    /// struct CheckoutButton: View {
    ///     @Environment(\.tracker) private var tracker
    ///
    ///     var body: some View {
    ///         Button("Check out") {
    ///             tracker.track(CheckoutStarted(cartSize: 3))
    ///         }
    ///     }
    /// }
    /// ```
    ///
    /// The environment reaches a button's action, where a `withTracker` binding doesn't: SwiftUI
    /// runs actions on tasks of its own. Inside a view given `trackScreen(_:)`, the tracker is
    /// one enriched with the screen, so every event tracked through it carries the screen's
    /// ``ScreenKey``. Until a tracker is set it is `Tracker.noOp`, which drops every event and
    /// logs it at debug level, so a view shown without one, such as in a preview, is safe.
    ///
    /// Where UIKit has traits (iOS, iPadOS, tvOS, visionOS and Mac Catalyst), it is the same
    /// value as UIKit's `TrackerTrait` (module `UIKitTracking`): SwiftUI views hosted in UIKit read
    /// the tracker of the scene or view controller around them, and UIKit views hosted in SwiftUI
    /// read the environment's as `traitCollection.tracker`.
    public var tracker: Tracker {
        get { self[TrackerKey.self] }
        set { self[TrackerKey.self] = newValue }
    }
}

/// The environment's tracker, `Tracker.noOp` until one is set.
// A key of its own rather than `@Entry`'s, so that it can be bridged to UIKit's trait below.
struct TrackerKey: EnvironmentKey {
    static let defaultValue: Tracker = .noOp
}

#if canImport(UIKit) && !os(watchOS)
// SwiftUITracking depends on UIKitTracking rather than the other way round: UIKit is the layer
// below, which needs nothing of SwiftUI's, and the bridge is SwiftUI's protocol, adopted by the
// environment's own key.
extension TrackerKey: UITraitBridgedEnvironmentKey {
    static func read(from traitCollection: UITraitCollection) -> Tracker {
        traitCollection.tracker
    }

    static func write(to mutableTraits: inout any UIMutableTraits, value: Tracker) {
        mutableTraits.tracker = value
    }
}
#endif

extension View {
    /// Sets the tracker that this view and the views inside it track their events through.
    ///
    /// - Parameter tracker: The tracker to put in the environment as `\.tracker`.
    /// - Returns: The view, with `tracker` in its environment.
    public func tracker(_ tracker: Tracker) -> some View {
        environment(\.tracker, tracker)
    }
}
#endif
