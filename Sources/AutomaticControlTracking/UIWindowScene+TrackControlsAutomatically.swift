#if canImport(UIKit) && !os(watchOS)
import Events
import ObjectiveC
public import UIKit

extension UIWindowScene {
    /// Tracks ``ControlActivated`` each time a touch activates a UIKit control in this scene's
    /// windows, until ``stopTrackingControlsAutomatically()``: a button tapped, a switch flipped,
    /// a segment chosen.
    ///
    /// Nothing is tracked automatically until this is called. Call it where the scene connects,
    /// beside setting its tracker:
    ///
    /// ```swift
    /// func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
    ///     guard let windowScene = scene as? UIWindowScene else { return }
    ///     windowScene.traitOverrides.tracker = tracker
    ///     windowScene.trackControlsAutomatically()
    /// }
    /// ```
    ///
    /// An activation is a control sending `.primaryActionTriggered`, `.touchUpInside` or
    /// `.valueChanged` after a touch began on it, before the next touch begins, tracked once per
    /// touch: a touch that ends outside the control, or that a scroll takes over, tracks nothing,
    /// and a slider dragged across its range tracks once. An action the app sends itself with
    /// `sendActions(for:)` isn't tracked, unless it goes to a control the last touch was on and
    /// didn't activate. Activations without a touch, such as from VoiceOver, a keyboard or a
    /// pointer's focus, aren't tracked. Each window the scene shows is watched, including those
    /// shown after this call.
    ///
    /// A control is named after its `accessibilityIdentifier`, never its title or other text
    /// it shows, which may be a person's data. `controlActivated` makes the event from each
    /// ``DiscoveredControl``, renaming it or returning `nil` to skip it; by default a control
    /// without an identifier is skipped. Each record's context carries the control's screen as
    /// `ScreenKey` (module `SwiftUITracking`), the type of the view controller it is in, unless
    /// the tracker's own enrichers set one.
    ///
    /// SwiftUI's controls are never tracked: a SwiftUI `Button` makes no UIKit control, and a
    /// UIKit control inside a SwiftUI view, such as one a `UIViewRepresentable` makes, is left
    /// out with them, so that no activation is tracked without the app's name for it. Give those
    /// `trackOnTap(_:)` or `UIControl.track(_:for:)`.
    ///
    /// Each activation goes through the tracker the control's traits hold
    /// (`traitCollection.tracker`), so two scenes keep their controls apart. Its call site is
    /// where this is called. Calling it again replaces what an earlier call set up; the scene
    /// keeps it until the scene ends or ``stopTrackingControlsAutomatically()`` is called. It
    /// swizzles nothing and touches no other scene: it adds a gesture recognizer to each of the
    /// scene's windows that only watches touches begin and end, never recognizing, delaying or
    /// cancelling one, and a target to each control a touch begins on.
    ///
    /// - Parameters:
    ///   - file: The caller's file; leave it to its default.
    ///   - fileID: The caller's module and file name; leave it to its default.
    ///   - function: The caller's enclosing declaration; leave it to its default.
    ///   - line: The caller's line; leave it to its default.
    ///   - column: The caller's column; leave it to its default.
    ///   - controlActivated: The event to track for an activated control, or `nil` to skip it; a
    ///     ``ControlActivated`` named after the control's identifier by default, and `nil` for a
    ///     control without one. It runs on the main actor as the control activates, so keep it
    ///     fast.
    public func trackControlsAutomatically(
        file: String = #file,
        fileID: String = #fileID,
        function: String = #function,
        line: Int = #line,
        column: Int = #column,
        _ controlActivated: @escaping @MainActor (DiscoveredControl) -> ControlActivated? = { control in
            control.identifier.map { ControlActivated(control: $0, kind: control.kind) }
        }
    ) {
        let discovery = ControlDiscovery(
            scene: self,
            controlActivated: controlActivated,
            callSite: SourceLocation(file: file, fileID: fileID, function: function, line: line, column: column)
        )
        // The scene owns its discovery, so it ends with the scene and no other scene shares it.
        // The one it replaces, if any, is released here, and takes its recognizers and targets
        // with it.
        objc_setAssociatedObject(self, ControlDiscovery.associationKey, discovery, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    /// Stops what ``trackControlsAutomatically(file:fileID:function:line:column:_:)`` set up in
    /// this scene; does nothing if it wasn't.
    public func stopTrackingControlsAutomatically() {
        objc_setAssociatedObject(self, ControlDiscovery.associationKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}
#endif
