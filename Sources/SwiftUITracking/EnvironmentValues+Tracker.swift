// SwiftUI is on Apple platforms alone; elsewhere this module builds empty, so the package still
// does.
#if canImport(SwiftUI)
public import SwiftUI
public import Trackers

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
    @Entry public var tracker: Tracker = .noOp
}

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
