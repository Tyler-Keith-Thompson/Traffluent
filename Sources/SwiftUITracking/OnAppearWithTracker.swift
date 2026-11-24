#if canImport(SwiftUI)
import SwiftUI
import Trackers

extension View {
    /// The view, running `action` with `tracker` each time it appears, or, when it appears before
    /// a tracker reaches it, once one does while it is still on screen.
    ///
    /// - Parameters:
    ///   - tracker: The tracker the view's environment holds.
    ///   - action: What to track through the tracker.
    /// - Returns: The view, running `action` once per appearance.
    func onAppear(with tracker: Tracker, perform action: @escaping (Tracker) -> Void) -> some View {
        modifier(OnAppearWithTracker(tracker: tracker, action: action))
    }
}

/// Runs its action once per appearance of its content, with the first tracker that isn't
/// `Tracker.noOp`.
// Why the wait: a view a `NavigationStack` pushes on iOS appears in a hosting controller of its
// own, before the controller joins its window, so its traits don't yet hold a tracker set on the
// window, nor one set with `tracker(_:)` around the stack: the trait bridge reads the
// controller's traits over the environment. The environment's tracker is `Tracker.noOp` as
// `onAppear` runs, then changes to the window's once the controller joins it; an appearance
// tracked at once would be dropped.
struct OnAppearWithTracker: ViewModifier {
    let tracker: Tracker
    let action: (Tracker) -> Void
    // Whether the content appeared without a tracker and is still on screen, waiting for one.
    @State private var isWaitingForTracker = false

    func body(content: Content) -> some View {
        content
            .onAppear { [tracker, action] in
                if tracker.isNoOp {
                    isWaitingForTracker = true
                } else {
                    action(tracker)
                }
            }
            .onChange(of: tracker.isNoOp) { [tracker, action] in
                guard isWaitingForTracker, !tracker.isNoOp else { return }
                isWaitingForTracker = false
                action(tracker)
            }
            .onDisappear {
                isWaitingForTracker = false
            }
    }
}
#endif
