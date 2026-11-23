#if canImport(SwiftUI) && canImport(UIKit) && !os(watchOS)
import Events
import ObjectiveC
public import SwiftUITracking
public import UIKit

extension UIWindowScene {
    /// Tracks `ScreenViewed` each time a screen appears in this scene's
    /// windows, until ``stopTrackingScreensAutomatically()``: a view controller pushed, presented
    /// or revealed again, or a SwiftUI view a hosting controller shows, such as one a
    /// `NavigationStack` pushes.
    ///
    /// Nothing is tracked automatically until this is called. Call it where the scene connects,
    /// beside setting its tracker:
    ///
    /// ```swift
    /// func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
    ///     guard let windowScene = scene as? UIWindowScene else { return }
    ///     windowScene.traitOverrides.tracker = tracker
    ///     windowScene.trackScreensAutomatically()
    /// }
    /// ```
    ///
    /// A screen is a view controller on screen none of whose children is: the one a navigation
    /// controller shows, a tab bar controller's selected one, one presented. Containers aren't
    /// screens. Each screen tracks once as it appears, and again when it reappears after being
    /// covered, such as when a navigation controller pops back to it, not while it stays on
    /// screen. Discovery looks after each turn of the main run loop, once no transition is
    /// running, so a pop the user cancels halfway tracks nothing. UIKit's own controllers, such as
    /// alerts, are never screens.
    ///
    /// A screen is named after its controller's type, `"CheckoutViewController"`, or for a
    /// hosting controller after the type of the SwiftUI view it shows, `"CheckoutView"`. A
    /// `NavigationStack`'s root view, whose type SwiftUI erases, takes the name of the hosting
    /// controller around the stack. `screenViewed` makes the event from each
    /// ``DiscoveredScreen``, renaming it or returning `nil` to skip it. A SwiftUI screen given
    /// `trackScreen(_:)` is left to it, and isn't tracked twice.
    ///
    /// Each screen view goes through the tracker the screen's traits hold
    /// (`traitCollection.tracker`): the scene's, or one set on a view controller above the screen,
    /// so two scenes keep their screens apart. Its call site is where this is called. Calling it
    /// again replaces what an earlier call set up, without tracking again the screens already on
    /// screen; the scene keeps it until the scene ends or ``stopTrackingScreensAutomatically()``
    /// is called. It swizzles nothing and touches no other scene.
    ///
    /// - Parameters:
    ///   - kinds: The kinds of screen to track; both UIKit's view controllers and SwiftUI's views
    ///     by default. Leave one out to track only the other.
    ///   - file: The caller's file; leave it to its default.
    ///   - fileID: The caller's module and file name; leave it to its default.
    ///   - function: The caller's enclosing declaration; leave it to its default.
    ///   - line: The caller's line; leave it to its default.
    ///   - column: The caller's column; leave it to its default.
    ///   - screenViewed: The event to track for a discovered screen, or `nil` to skip it; a
    ///     `ScreenViewed` with the screen's name by default. It runs on the main
    ///     actor as the screen appears, so keep it fast.
    public func trackScreensAutomatically(
        kinds: Set<DiscoveredScreen.Kind> = [.uiKit, .swiftUI],
        file: String = #file,
        fileID: String = #fileID,
        function: String = #function,
        line: Int = #line,
        column: Int = #column,
        _ screenViewed: @escaping @MainActor (DiscoveredScreen) -> ScreenViewed? = { ScreenViewed(screen: $0.name) }
    ) {
        let discovery = ScreenDiscovery(
            kinds: kinds,
            screenViewed: screenViewed,
            callSite: SourceLocation(file: file, fileID: fileID, function: function, line: line, column: column),
            replacing: objc_getAssociatedObject(self, ScreenDiscovery.associationKey) as? ScreenDiscovery
        ) { [weak self] in
            (self?.windows ?? []).filter { !$0.isHidden }.compactMap(\.rootViewController)
        }
        // The scene owns its discovery, so it ends with the scene and no other scene shares it.
        objc_setAssociatedObject(self, ScreenDiscovery.associationKey, discovery, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    /// Stops what ``trackScreensAutomatically(kinds:file:fileID:function:line:column:_:)`` set
    /// up in this scene; does nothing if it wasn't.
    public func stopTrackingScreensAutomatically() {
        objc_setAssociatedObject(self, ScreenDiscovery.associationKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}
#endif
