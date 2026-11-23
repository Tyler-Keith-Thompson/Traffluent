// AppKit is the Mac's alone; Mac Catalyst can import it but builds its views with UIKit
// (UIKitTracking). Elsewhere this module builds empty, so the package still does.
#if canImport(AppKit) && !targetEnvironment(macCatalyst)
public import Trackers

/// Something that holds the tracker for the views its actions come from: a window controller, a
/// view controller, a window, a window's delegate or the application's delegate.
///
/// AppKit has no environment for views to inherit, so a view finds its tracker the way AppKit
/// finds the target of an action sent to the first responder: ``AppKit/NSView/tracker`` asks the
/// view, its superviews and their view controllers, its window and window controller, then the
/// window's delegate and the application's delegate, and takes the first that conforms. Conform
/// the window controller to give each window a tracker of its own:
///
/// ```swift
/// final class DocumentWindowController: NSWindowController, TrackerProviding {
///     let tracker: Tracker
///
///     init(window: NSWindow, tracker: Tracker) {
///         self.tracker = tracker
///         super.init(window: window)
///     }
///
///     required init?(coder: NSCoder) { nil }
/// }
/// ```
///
/// A view controller that conforms gives the views below it its own, such as a tracker enriched
/// with a screen's name. A view can't conform: `NSView.tracker` is the lookup itself.
@MainActor
public protocol TrackerProviding: AnyObject {
    /// The tracker for the views whose actions reach this object.
    var tracker: Tracker { get }
}
#endif
