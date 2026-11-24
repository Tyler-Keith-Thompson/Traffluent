#if canImport(SwiftUI)
public import SwiftUI
import Instrumentation
import Trackers

extension View {
    /// Makes this view the screen named `screen`: it tracks ``ScreenViewed`` each time the view
    /// appears, and every event tracked from inside it carries `screen` as its ``ScreenKey``.
    ///
    /// ```swift
    /// CheckoutView()
    ///     .trackScreen("Checkout")
    /// ```
    ///
    /// Inside the view, the environment's tracker is the one from outside enriched with the
    /// screen, so a button's action that tracks through `@Environment(\.tracker)`, and the
    /// tracking modifiers applied inside the screen, stamp each record's context with
    /// `context[ScreenKey.self] == screen`. A modifier applied after `trackScreen(_:)`, outside
    /// it, doesn't. A screen inside another sets its own name for the views inside it.
    ///
    /// Apply it where the screen's view is placed, as above, rather than in that view's own
    /// `body`: a view's `@Environment(\.tracker)` reads the environment it is placed in, which
    /// the modifiers of its own body don't change, so only the views inside the body would see
    /// the screen.
    ///
    /// It tracks ``ScreenViewed`` once per appearance, as `onAppear(perform:)` runs: again when
    /// the view reappears, such as when a navigation stack pops back to it, and not when SwiftUI
    /// only redraws it. A view that appears before a tracker reaches it, such as a view a
    /// `NavigationStack` pushes in UIKit, whose traits gain their window's tracker only after it
    /// appears, tracks once one does, while it is still on screen. The record's call site is
    /// where the modifier is applied.
    ///
    /// - Parameters:
    ///   - screen: The screen's name.
    ///   - file: The caller's file; leave it to its default.
    ///   - fileID: The caller's module and file name; leave it to its default.
    ///   - function: The caller's enclosing declaration; leave it to its default.
    ///   - line: The caller's line; leave it to its default.
    ///   - column: The caller's column; leave it to its default.
    /// - Returns: The view, tracked as the screen named `screen`.
    public func trackScreen(
        _ screen: String,
        file: String = #file,
        fileID: String = #fileID,
        function: String = #function,
        line: Int = #line,
        column: Int = #column
    ) -> some View {
        modifier(TrackScreen(screen: screen, callSite: CallSite(file: file, fileID: fileID, function: function, line: line, column: column)))
    }
}

/// Puts a tracker enriched with its screen in its content's environment, and tracks the screen's
/// view each time the content appears.
struct TrackScreen: ViewModifier {
    let screen: String
    let callSite: CallSite
    @Environment(\.tracker) private var tracker

    func body(content: Content) -> some View {
        // An environment value rather than a task-local ServiceContext: SwiftUI runs a button's
        // action on a task of its own, which a task-local doesn't reach, but the action reads the
        // environment of the view it is in.
        let screenTracker = tracker.enriched(by: Enricher { [screen] context in
            context[ScreenKey.self] = screen
        })
        content
            .environment(\.tracker, screenTracker)
            .onAppear(with: screenTracker) { [screen, callSite] screenTracker in
                screenTracker.track(ScreenViewed(screen: screen), from: callSite)
            }
            .markedAsTrackedScreen()
    }
}

extension View {
    /// The view, holding a `TrackedScreenMarker` behind it where UIKit or AppKit hosts it, so
    /// automatic screen tracking leaves its screen to `trackScreen(_:)`.
    @ViewBuilder
    fileprivate func markedAsTrackedScreen() -> some View {
        #if (canImport(UIKit) && !os(watchOS)) || canImport(AppKit)
        background(TrackedScreenMarker())
        #else
        self
        #endif
    }
}
#endif
