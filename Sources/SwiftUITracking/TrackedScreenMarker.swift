// What `trackScreen(_:)` leaves in the platform's view hierarchy, so that automatic screen tracking
// (module AutomaticScreenTracking) finds the screens tracked by hand and leaves them to it. A
// view, rather than a flag set from SwiftUI: a hosting controller exposes nothing of the
// environment or preferences inside its root view, but a representable's view sits in its view
// hierarchy, where any code can look, with public API alone. Only UIKit and AppKit platforms
// discover screens; watchOS has no views to mark.
#if canImport(SwiftUI) && canImport(UIKit) && !os(watchOS)
import UIKit
package import SwiftUI

/// The empty view a screen tracked with `trackScreen(_:)` holds, which automatic screen tracking
/// takes as the sign that the screen is tracked by hand.
package final class TrackedScreenMarkerView: UIView {}

/// Places a ``TrackedScreenMarkerView`` behind a screen's content.
struct TrackedScreenMarker: UIViewRepresentable {
    func makeUIView(context: Context) -> TrackedScreenMarkerView {
        let view = TrackedScreenMarkerView()
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        return view
    }

    func updateUIView(_ uiView: TrackedScreenMarkerView, context: Context) {}
}
#elseif canImport(SwiftUI) && canImport(AppKit)
import AppKit
package import SwiftUI

/// The empty view a screen tracked with `trackScreen(_:)` holds, which automatic screen tracking
/// takes as the sign that the screen is tracked by hand.
package final class TrackedScreenMarkerView: NSView {
    // Clicks pass through to the screen's own views.
    package override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Places a ``TrackedScreenMarkerView`` behind a screen's content.
struct TrackedScreenMarker: NSViewRepresentable {
    func makeNSView(context: Context) -> TrackedScreenMarkerView {
        let view = TrackedScreenMarkerView()
        view.setAccessibilityElement(false)
        return view
    }

    func updateNSView(_ nsView: TrackedScreenMarkerView, context: Context) {}
}
#endif
