#if canImport(UIKit) && !os(watchOS)
public import Events
import Trackers
public import UIKit

// `Events.Event`, since inside UIControl `Event` names `UIControl.Event`.
extension UIControl {
    /// Tracks `event` each time the control sends `controlEvents`, through the tracker its traits
    /// hold at that moment, beside the control's own actions.
    ///
    /// ```swift
    /// let button = UIButton(configuration: .filled(), primaryAction: UIAction(title: "Share") { _ in share() })
    /// button.track(ShareTapped())
    /// ```
    ///
    /// It adds a `UIAction` for `controlEvents`, without replacing the control's other actions or
    /// targets, so the control still runs them. Each time the action fires, it reads the
    /// control's `traitCollection.tracker`: the ``TrackerTrait`` of the scene, view controller or
    /// view the control is in then, not when `track` was called. A control moved to another
    /// window tracks through that window's tracker. The record's call site is where `track` is
    /// called.
    ///
    /// - Parameters:
    ///   - event: The event to track each time the control sends `controlEvents`.
    ///   - controlEvents: The control events that track `event`; `.primaryActionTriggered`, a
    ///     button's tap, by default.
    ///   - file: The caller's file; leave it to its default.
    ///   - fileID: The caller's module and file name; leave it to its default.
    ///   - function: The caller's enclosing declaration; leave it to its default.
    ///   - line: The caller's line; leave it to its default.
    ///   - column: The caller's column; leave it to its default.
    /// - Returns: The action added to the control; pass it to `removeAction(_:for:)` to stop
    ///   tracking.
    @discardableResult
    public func track(
        _ event: some Events.Event,
        for controlEvents: UIControl.Event = .primaryActionTriggered,
        file: String = #file,
        fileID: String = #fileID,
        function: String = #function,
        line: Int = #line,
        column: Int = #column
    ) -> UIAction {
        // Weak, since the control holds the action: a strong capture would keep both alive.
        let action = UIAction { [weak self] _ in
            self?.traitCollection.tracker.track(event, file: file, fileID: fileID, function: function, line: line, column: column)
        }
        addAction(action, for: controlEvents)
        return action
    }
}
#endif
