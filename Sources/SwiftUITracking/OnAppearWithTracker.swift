#if canImport(SwiftUI)
import SwiftUI
import Trackers

extension View {
    /// The view, running `action` with `tracker` each time it appears, or, when it appears before
    /// it is in its window or before a tracker reaches it, once both are true while it is still on
    /// screen.
    ///
    /// - Parameters:
    ///   - tracker: The tracker the view's environment holds.
    ///   - action: What to track through the tracker.
    /// - Returns: The view, running `action` once per appearance.
    func onAppear(with tracker: Tracker, perform action: @escaping (Tracker) -> Void) -> some View {
        modifier(OnAppearWithTracker(tracker: tracker, action: action))
    }
}

/// Runs its action once per appearance of its content, with the environment's tracker once the
/// content is in its window and the tracker isn't `Tracker.noOp`.
// Why the wait: a view a `NavigationStack` pushes on iOS appears in a hosting controller of its
// own, before the controller joins its window. The trait bridge reads the controller's traits
// over the environment, so the environment's tracker is then the scene's (the never-set default
// when the scene has none), not a tracker set on the window nor one set with `tracker(_:)` around
// the stack. Once the controller joins the window, its traits, and the environment, hold the
// window's; an appearance tracked at once would reach the scene's tracker, or the bootstrapped
// one. A never-set tracker isn't waited past once the view is in its window: it tracks as
// `Tracker.current` does, so a forgotten tracker warns rather than leaving the view waiting
// silently for ever.
struct OnAppearWithTracker: ViewModifier {
    let tracker: Tracker
    let action: (Tracker) -> Void
    // Whether the content appeared and is still on screen, waiting for its window or a tracker.
    @State private var isWaiting = false
    #if canImport(UIKit) && !os(watchOS)
    @State private var windowState = WindowState()
    #endif

    func body(content: Content) -> some View {
        placed(content)
            .onAppear { [tracker, action] in
                if isReady(tracker) {
                    action(tracker)
                } else {
                    isWaiting = true
                }
            }
            .onChange(of: isReady(tracker)) { [tracker, action] in
                guard isWaiting, isReady(tracker) else { return }
                isWaiting = false
                action(tracker)
            }
            .onDisappear {
                isWaiting = false
            }
    }
}

extension OnAppearWithTracker {
    /// The content, with a ``WindowStateReader`` behind it where UIKit hosts it.
    @ViewBuilder
    fileprivate func placed(_ content: Content) -> some View {
        #if canImport(UIKit) && !os(watchOS)
        content.background(WindowStateReader(state: windowState))
        #else
        content
        #endif
    }

    /// Whether an appearance can be tracked through `tracker`: the content is in its window, so
    /// the environment holds that window's tracker, and the tracker isn't `Tracker.noOp`.
    fileprivate func isReady(_ tracker: Tracker) -> Bool {
        #if canImport(UIKit) && !os(watchOS)
        windowState.isInWindow && !tracker.isNoOp
        #else
        // AppKit hosts a view in its window before it appears.
        !tracker.isNoOp
        #endif
    }
}
#endif
