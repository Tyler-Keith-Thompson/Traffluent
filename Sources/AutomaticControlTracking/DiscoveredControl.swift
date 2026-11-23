// Controls are discovered where UIKit draws them: iOS, iPadOS, tvOS, visionOS and Mac Catalyst.
// The event, ControlActivated, builds everywhere; the discovery is UIKit's alone.
#if canImport(UIKit) && !os(watchOS)

/// A control that automatic control tracking saw activated by a touch: what its predicate turns
/// into a ``ControlActivated``, or skips.
///
/// It carries no title, label or text the control shows, which may be a person's data: only the
/// identifier the app gave it, its kind and its screen.
///
/// ```swift
/// windowScene.trackControlsAutomatically { control in
///     switch control.identifier {
///     case nil, "debug-menu": nil  // not tracked
///     case "checkout-button": ControlActivated(control: "Checkout", kind: control.kind)
///     case let identifier?: ControlActivated(control: identifier, kind: control.kind)
///     }
/// }
/// ```
public struct DiscoveredControl: Sendable, Hashable {
    /// The control's `accessibilityIdentifier`, or `nil` if it has none or an empty one.
    public var identifier: String?

    /// The first public UIKit class the control is an instance of, such as `"UIButton"` for a
    /// `UIButton` or a subclass the app declares.
    public var kind: String

    /// The name of the screen the control is on: the type of the nearest view controller above it
    /// that isn't one of UIKit's own, such as `"CheckoutViewController"`; `nil` if there is none.
    public var screen: String?

    /// The control with `identifier`, of kind `kind`, on `screen`.
    ///
    /// - Parameters:
    ///   - identifier: The control's accessibility identifier, if it has one.
    ///   - kind: The control's kind.
    ///   - screen: The control's screen's name, if it is known.
    public init(identifier: String?, kind: String, screen: String?) {
        self.identifier = identifier
        self.kind = kind
        self.screen = screen
    }
}
#endif
