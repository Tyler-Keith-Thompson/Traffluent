#if canImport(SwiftUI)
public import Events
public import SwiftUI
import Trackers

extension View {
    /// Tracks `event` through the environment's tracker each time this view appears.
    ///
    /// ```swift
    /// CartView()
    ///     .trackOnAppear(CartOpened())
    /// ```
    ///
    /// It tracks once per appearance, as `onAppear(perform:)` runs: again when the view
    /// reappears, such as when a navigation stack pops back to it or a tab is selected again, and
    /// not when SwiftUI only redraws it. Where UIKit hosts the view, it tracks once the view is in
    /// its window, through that window's tracker: a view a `NavigationStack` pushes appears
    /// before its hosting controller joins the window, holding the scene's tracker until then,
    /// or none. A view that appears while its tracker is `Tracker.noOp` tracks once another
    /// reaches it, while it is still on screen. One whose tracker was never set tracks without
    /// waiting for a tracker, as `Tracker.current` does with nothing bound. The record's call site
    /// is where the modifier is applied.
    ///
    /// - Parameters:
    ///   - event: The event to track on each appearance.
    ///   - file: The caller's file; leave it to its default.
    ///   - fileID: The caller's module and file name; leave it to its default.
    ///   - function: The caller's enclosing declaration; leave it to its default.
    ///   - line: The caller's line; leave it to its default.
    ///   - column: The caller's column; leave it to its default.
    /// - Returns: The view, tracking `event` each time it appears.
    public func trackOnAppear(
        _ event: some Event,
        file: String = #file,
        fileID: String = #fileID,
        function: String = #function,
        line: Int = #line,
        column: Int = #column
    ) -> some View {
        modifier(TrackOnAppear(event: event, callSite: CallSite(file: file, fileID: fileID, function: function, line: line, column: column)))
    }
}

/// Tracks its event each time its content appears.
struct TrackOnAppear<Tracked: Event>: ViewModifier {
    let event: Tracked
    let callSite: CallSite
    @Environment(\.tracker) private var tracker

    func body(content: Content) -> some View {
        content.onAppear(with: tracker) { [event, callSite] tracker in
            tracker.track(event, from: callSite)
        }
    }
}
#endif
