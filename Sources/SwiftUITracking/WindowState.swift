// Whether a SwiftUI view's UIKit host has joined its window: the signal OnAppearWithTracker waits
// for. A representable's view, rather than anything of SwiftUI's: SwiftUI runs `onAppear` for a
// view a `NavigationStack` pushes before its hosting controller joins the window, and exposes no
// window of its own, but a UIKit view placed beside the content is told, with public API alone,
// when it moves to a window. AppKit hosts views in their window before they appear, and watchOS
// has no traits, so only UIKit needs it.
#if canImport(SwiftUI) && canImport(UIKit) && !os(watchOS)
import SwiftUI
import UIKit

/// Whether the view a ``WindowStateReader`` sits behind is in a window.
// A reference, observed, rather than a value in `@State`: the UIKit view writes it as it moves,
// outside SwiftUI's updates, and `onAppear` reads it at once, where a binding's write would show
// only in the next update.
@MainActor
@Observable
final class WindowState {
    /// Whether the view is in a window.
    var isInWindow = false
}

/// Places a ``WindowStateView`` behind a view's content, writing to `state` whether it is in a
/// window.
struct WindowStateReader: UIViewRepresentable {
    let state: WindowState

    func makeUIView(context: Context) -> WindowStateView {
        let view = WindowStateView()
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        view.state = state
        return view
    }

    func updateUIView(_ uiView: WindowStateView, context: Context) {}
}

/// The empty view a ``WindowStateReader`` places, which writes whether it is in a window as it
/// moves.
final class WindowStateView: UIView {
    var state: WindowState?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        state?.isInWindow = window != nil
    }
}
#endif
