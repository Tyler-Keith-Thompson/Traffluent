// Screens are discovered where UIKit or AppKit hosts them: iOS, iPadOS, tvOS, visionOS, Mac
// Catalyst and macOS. watchOS has no view controllers, and Linux no UI; there this module builds
// empty, so the package still does.
#if canImport(SwiftUI) && ((canImport(UIKit) && !os(watchOS)) || canImport(AppKit))

/// A screen that automatic screen tracking found appearing: what its predicate turns into a
/// `ScreenViewed`, or skips.
///
/// ```swift
/// windowScene.trackScreensAutomatically { screen in
///     switch screen.name {
///     case "DebugMenuView": nil  // not tracked
///     case "CheckoutViewController": ScreenViewed(screen: "Checkout")
///     default: ScreenViewed(screen: screen.name)
///     }
/// }
/// ```
public struct DiscoveredScreen: Sendable, Hashable {
    /// What draws a screen: a view controller of UIKit's or AppKit's, or a SwiftUI view in a
    /// hosting controller.
    public enum Kind: Sendable, Hashable, CaseIterable {
        /// A `UIViewController` other than a `UIHostingController`: iOS, iPadOS, tvOS, visionOS and
        /// Mac Catalyst.
        case uiKit
        /// An `NSViewController` other than an `NSHostingController`: macOS.
        case appKit
        /// A SwiftUI view, hosted by a `UIHostingController` or an `NSHostingController`, such as a
        /// view a `NavigationStack` pushes on iOS.
        case swiftUI
    }

    /// The screen's name: its view controller's type, or for SwiftUI the type of the view the
    /// hosting controller shows, without its module, such as `"CheckoutViewController"` or
    /// `"CheckoutView"`.
    ///
    /// A `NavigationStack`'s root view, whose type SwiftUI erases, takes the name of the hosting
    /// controller around the stack. A destination that picks its view with an `if` or a `switch`
    /// over the value it presents is named after that value: an enumeration's type and case,
    /// without associated values (`"Route.settings"`), or another value's type. A hosting
    /// controller whose view holds no type of the app's takes its own type's name.
    public var name: String

    /// What draws the screen.
    public var kind: Kind

    /// The screen named `name`, drawn by `kind`.
    ///
    /// - Parameters:
    ///   - name: The screen's name.
    ///   - kind: What draws the screen.
    public init(name: String, kind: Kind) {
        self.name = name
        self.kind = kind
    }
}
#endif
