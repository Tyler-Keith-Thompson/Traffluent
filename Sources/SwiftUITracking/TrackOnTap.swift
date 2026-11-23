#if canImport(SwiftUI)
public import Events
public import SwiftUI
import Trackers

extension View {
    /// Tracks `event` through the environment's tracker each time this view is tapped, beside
    /// the view's own action.
    ///
    /// ```swift
    /// Button("Share") { share() }
    ///     .trackOnTap(ShareTapped())
    /// ```
    ///
    /// It tracks once per tap SwiftUI recognizes, through a tap gesture recognized together with
    /// the view's own gestures, so a button still runs its action and a tap that the view's
    /// gestures also use is tracked too. The record's call site is where the modifier is applied.
    ///
    /// - Parameters:
    ///   - event: The event to track on each tap.
    ///   - file: The caller's file; leave it to its default.
    ///   - fileID: The caller's module and file name; leave it to its default.
    ///   - function: The caller's enclosing declaration; leave it to its default.
    ///   - line: The caller's line; leave it to its default.
    ///   - column: The caller's column; leave it to its default.
    /// - Returns: The view, tracking `event` on each tap.
    public func trackOnTap(
        _ event: some Event,
        file: String = #file,
        fileID: String = #fileID,
        function: String = #function,
        line: Int = #line,
        column: Int = #column
    ) -> some View {
        modifier(TrackOnTap(event: event, callSite: CallSite(file: file, fileID: fileID, function: function, line: line, column: column)))
    }
}

/// Tracks its event each time its content is tapped.
struct TrackOnTap<Tracked: Event>: ViewModifier {
    let event: Tracked
    let callSite: CallSite
    @Environment(\.tracker) private var tracker

    func body(content: Content) -> some View {
        // Simultaneous, so the tap doesn't take the place of the content's own gestures, such as
        // a button's action.
        content.simultaneousGesture(TapGesture().onEnded { [tracker, event, callSite] in
            tracker.track(event, from: callSite)
        })
    }
}
#endif
