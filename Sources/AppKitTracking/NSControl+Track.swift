#if canImport(AppKit) && !targetEnvironment(macCatalyst)
public import AppKit
public import Events
import ObjectiveC
import Trackers

extension NSControl {
    /// Tracks `event` each time the control sends its action, through the tracker it finds then,
    /// before the action is sent.
    ///
    /// ```swift
    /// let button = NSButton(title: "Share", target: self, action: #selector(share(_:)))
    /// button.track(ShareTapped())
    /// ```
    ///
    /// A control has one target and action, so `track` puts an object of its own in their place,
    /// which tracks `event` and then sends the action the control had to the target it had, as
    /// the control would have: to the first responder when it had no target. Call it after
    /// setting the control's target and action; setting them afterwards replaces the tracking.
    /// Calling it again tracks both events, the newest first. The tracker is the control's
    /// ``AppKit/NSView/tracker``, found anew each time the action is sent, so a control moved to
    /// another window tracks through that window's tracker. The record's call site is where
    /// `track` is called.
    ///
    /// - Parameters:
    ///   - event: The event to track each time the control sends its action.
    ///   - file: The caller's file; leave it to its default.
    ///   - fileID: The caller's module and file name; leave it to its default.
    ///   - function: The caller's enclosing declaration; leave it to its default.
    ///   - line: The caller's line; leave it to its default.
    ///   - column: The caller's column; leave it to its default.
    public func track(
        _ event: some Event,
        file: String = #file,
        fileID: String = #fileID,
        function: String = #function,
        line: Int = #line,
        column: Int = #column
    ) {
        let tracking = TrackingAction(target: target, action: action) { control in
            control.tracker.track(event, file: file, fileID: fileID, function: function, line: line, column: column)
        }
        // A control holds its target weakly, so the control keeps the tracking action alive as an
        // associated object, under the action's own address: a key no other object shares, so a
        // second `track` keeps the first one's action too. Rejected: subclassing the control,
        // which every control class in the app would need, and swizzling `sendAction(_:to:)`.
        objc_setAssociatedObject(self, Unmanaged.passUnretained(tracking).toOpaque(), tracking, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        target = tracking
        action = #selector(TrackingAction.send(_:))
    }
}

/// A control's target in place of the one it had: tracks an event, then sends the control's own
/// action to its own target.
@MainActor
final class TrackingAction: NSObject {
    // Weak, as the control held it.
    private weak var target: AnyObject?
    private let action: Selector?
    private let track: (NSControl) -> Void

    init(target: AnyObject?, action: Selector?, track: @escaping (NSControl) -> Void) {
        self.target = target
        self.action = action
        self.track = track
    }

    @objc func send(_ sender: NSControl) {
        track(sender)
        if let action {
            sender.sendAction(action, to: target)
        }
    }
}
#endif
