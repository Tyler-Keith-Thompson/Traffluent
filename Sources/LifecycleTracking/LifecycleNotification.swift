import Foundation
#if canImport(UIKit) && !os(watchOS)
import UIKit
#elseif os(watchOS)
import WatchKit
#elseif canImport(AppKit)
import AppKit
#endif

/// A platform notification of a lifecycle transition, and which transition it is.
struct LifecycleNotification: Sendable {
    /// A transition a notification reports.
    enum Signal: Sendable {
        case enteredForeground
        case enteredBackground
        case terminated
    }

    let name: Notification.Name
    let signal: Signal

    /// The notifications this platform posts for the app's transitions; none on Linux, whose
    /// processes have no lifecycle but starting and ending.
    ///
    /// The application's notifications, not each scene's: a scene-based app posts them too, once
    /// for the whole app, where a scene's would track a transition per scene.
    static var all: [LifecycleNotification] {
        #if canImport(UIKit) && !os(watchOS)
        [
            LifecycleNotification(name: UIApplication.willEnterForegroundNotification, signal: .enteredForeground),
            LifecycleNotification(name: UIApplication.didEnterBackgroundNotification, signal: .enteredBackground),
            LifecycleNotification(name: UIApplication.willTerminateNotification, signal: .terminated),
        ]
        #elseif os(watchOS)
        // watchOS reports no termination.
        [
            LifecycleNotification(name: WKApplication.willEnterForegroundNotification, signal: .enteredForeground),
            LifecycleNotification(name: WKApplication.didEnterBackgroundNotification, signal: .enteredBackground),
        ]
        #elseif canImport(AppKit)
        // A Mac app isn't suspended in the background: it moves there, as far as anyone using it
        // can tell, when another app becomes the active one.
        [
            LifecycleNotification(name: NSApplication.didBecomeActiveNotification, signal: .enteredForeground),
            LifecycleNotification(name: NSApplication.didResignActiveNotification, signal: .enteredBackground),
            LifecycleNotification(name: NSApplication.willTerminateNotification, signal: .terminated),
        ]
        #else
        []
        #endif
    }
}
