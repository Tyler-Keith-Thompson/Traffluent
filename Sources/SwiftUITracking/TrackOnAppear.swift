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
    /// not when SwiftUI only redraws it. A view that appears before a tracker reaches it, such as a
    /// view a `NavigationStack` pushes in UIKit, whose traits gain their window's tracker only
    /// after it appears, tracks once one does, while it is still on screen. The record's call
    /// site is where the modifier is applied.
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
