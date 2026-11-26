#if canImport(AppKit) && !targetEnvironment(macCatalyst)
public import AppKit
public import Trackers

extension NSView {
    /// The tracker this view tracks its events through: that of the first ``TrackerProviding``
    /// its actions reach.
    ///
    /// It asks, in order, the view's responder chain (the view, its superviews and their view
    /// controllers, its window and the window's controller), the window's delegate and the
    /// application's delegate: the objects an action sent to the first responder of the view's
    /// window reaches. It is read anew each time, so a view moved to
    /// another window tracks through that window's tracker.
    ///
    /// A view below no provider tracks as `Tracker.current` does with nothing bound: through the
    /// tracker `Tracker.bootstrap(_:)` made the process's default, looked up as each event is
    /// tracked. With none bootstrapped it drops each event, logging the first from each call site
    /// at warning level, so a missing provider shows up in the logs. In an Xcode preview it gets
    /// `Tracker.noOp` instead, which drops every event quietly.
    ///
    /// ```swift
    /// @IBAction func checkOut(_ sender: NSButton) {
    ///     sender.tracker.track(CheckoutStarted(cartSize: 3))
    /// }
    /// ```
    ///
    /// - Complexity: O(*n*), where *n* is the length of the view's responder chain.
    public var tracker: Tracker {
        let provider = sequence(first: self as NSResponder, next: \.nextResponder)
            .lazy
            .compactMap { $0 as? TrackerProviding }
            .first
            ?? window?.delegate as? TrackerProviding
            ?? NSApp?.delegate as? TrackerProviding
        return provider?.tracker ?? .viewDefault
    }
}
#endif
