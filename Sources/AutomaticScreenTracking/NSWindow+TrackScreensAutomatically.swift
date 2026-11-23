#if canImport(SwiftUI) && canImport(AppKit) && !targetEnvironment(macCatalyst)
public import AppKit
import Events
import ObjectiveC
public import SwiftUITracking

extension NSWindow {
    /// Tracks `ScreenViewed` each time a screen appears in this window, until
    /// ``stopTrackingScreensAutomatically()``: a view controller shown in the window's content
    /// view controller, or presented from one, or a SwiftUI view an `NSHostingController` shows.
    ///
    /// Nothing is tracked automatically until this is called. Call it as the window is made, such
    /// as in its window controller's `windowDidLoad()`:
    ///
    /// ```swift
    /// override func windowDidLoad() {
    ///     super.windowDidLoad()
    ///     window?.trackScreensAutomatically()
    /// }
    /// ```
    ///
    /// A screen is a view controller on screen none of whose children is, at or below the
    /// window's `contentViewController`: a tab view controller's selected one, a split view
    /// controller's panes, one presented as a sheet. Containers aren't screens. Each screen tracks
    /// once as it appears, and again when it reappears after being hidden or removed, not while
    /// it stays on screen. Discovery looks after each turn of the main run loop. AppKit's own
    /// controllers are never screens, and a window without a content view controller has none.
    ///
    /// A screen is named after its controller's type, `"PreferencesViewController"`, or for an
    /// `NSHostingController` after the type of its root view, `"PreferencesView"`. A
    /// `NavigationStack` on macOS draws what it pushes inside its own hosting view, with no view
    /// controller or view of its own, so its pushes aren't discovered: give those views
    /// `trackScreen(_:)`. `screenViewed` makes the event from each ``DiscoveredScreen``, renaming
    /// it or returning `nil` to skip it. A SwiftUI screen given `trackScreen(_:)` is left to it,
    /// and isn't tracked twice.
    ///
    /// Each screen view goes through the tracker the screen's view finds
    /// (`NSView.tracker`, from module `AppKitTracking`), up its responder chain, so each window
    /// can keep its own. Its call site is where this is called. Calling it again replaces what an
    /// earlier call set up, without tracking again the screens already on screen; the window keeps
    /// it until it is deallocated or ``stopTrackingScreensAutomatically()`` is called. It swizzles
    /// nothing and touches no other window.
    ///
    /// - Parameters:
    ///   - kinds: The kinds of screen to track; both AppKit's view controllers and SwiftUI's views
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
        kinds: Set<DiscoveredScreen.Kind> = [.appKit, .swiftUI],
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
            (self?.contentViewController).map { [$0] } ?? []
        }
        // The window owns its discovery, so it ends with the window and no other window shares it.
        objc_setAssociatedObject(self, ScreenDiscovery.associationKey, discovery, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    /// Stops what ``trackScreensAutomatically(kinds:file:fileID:function:line:column:_:)`` set
    /// up in this window; does nothing if it wasn't.
    public func stopTrackingScreensAutomatically() {
        objc_setAssociatedObject(self, ScreenDiscovery.associationKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}
#endif
