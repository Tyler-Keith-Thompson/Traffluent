# Automatic Tracking

Track screen views, control activations and the app's lifecycle without a call at each place they happen.

## Overview

Each kind of automatic tracking is off until the app turns it on, and none swizzles: the window
scene, window or tracker that turns it on owns it.

### Screen views

Screens can track their own views (module ``/AutomaticScreenTracking``: iOS, iPadOS, tvOS,
visionOS, Mac Catalyst and macOS). Nothing is tracked until a window scene, or on macOS a window,
turns it on:

```swift
import AutomaticScreenTracking

// In the scene delegate's scene(_:willConnectTo:options:), beside the scene's tracker:
windowScene.traitOverrides.tracker = tracker
windowScene.trackScreensAutomatically { screen in
    switch screen.name {
    case "DebugMenuViewController": nil  // not tracked
    case "CheckoutView": ScreenViewed(screen: "Checkout")
    default: ScreenViewed(screen: screen.name)
    }
}
```

A screen is a view controller on screen with no child view controller on screen: the one a
navigation controller shows, a tab's, one presented. It tracks `ScreenViewed` as it appears, and
again when a pop or a dismissal reveals it. The screen is named after its controller's type, or,
for a hosting controller, after the SwiftUI view it shows, such as each view a `NavigationStack`
pushes on iOS.

The closure gets each `DiscoveredScreen`, with its name and kind, and returns the event to track,
renamed, or `nil` to skip the screen. Leave the closure out to track every screen under its own
name. `kinds:` turns off UIKit's (or AppKit's) view controllers or SwiftUI's views. A SwiftUI
screen given `trackScreen(_:)` is left to that modifier, so it isn't tracked twice.

Each screen view goes through the tracker the screen's traits hold, so each scene keeps its own. On
macOS, `window.trackScreensAutomatically()` tracks through the tracker the screen's view finds up
its responder chain. A `NavigationStack` there draws what it pushes without a view controller, so
give those views `trackScreen(_:)`. The scene looks at its view controllers after each turn of the
main run loop.

### Control activations

UIKit controls can track their own activations too (module ``/AutomaticControlTracking``: iOS,
iPadOS, tvOS, visionOS and Mac Catalyst). Nothing is tracked until a window scene turns it on:

```swift
import AutomaticControlTracking

// In the scene delegate's scene(_:willConnectTo:options:), beside the scene's tracker:
windowScene.traitOverrides.tracker = tracker
windowScene.trackControlsAutomatically { control in
    switch control.identifier {
    case "debug-menu-button": nil  // not tracked
    case "checkout-button": ControlActivated(control: "Checkout", kind: control.kind)
    case let identifier?: ControlActivated(control: identifier, kind: control.kind)
    case nil: nil  // no identifier: not tracked
    }
}
```

Each time a touch activates a UIKit control in the scene's windows (a button tapped, a switch
flipped), the scene tracks one `ControlActivated`. It is named after the control's
`accessibilityIdentifier`, never its title or other text, and carries the control's kind, the first
public UIKit class it is (`"UIButton"`). The closure gets each `DiscoveredControl`, with its
identifier, kind and screen, and returns the event, renamed, or `nil` to skip it. Leave the closure
out to track every control that has an identifier, under that identifier.

A touch that ends off the control tracks nothing. Neither do activations without a touch, such as
VoiceOver's, nor actions the app sends itself, except to a control the last touch was on and didn't
activate. Each record's context carries the control's screen, the type of the view controller it is
in, as `ScreenKey`, unless the tracker's enrichers set one.

SwiftUI's controls are never tracked automatically: give them `trackOnTap(_:)`. A UIKit control
inside a SwiftUI view is left out with them. Each activation goes through the tracker the control's
traits hold, so each scene keeps its own. The scene adds a gesture recognizer to each of its
windows that notes the control a touch begins on and never recognizes, so it holds up no touch, and
adds a target to that control. macOS has no equivalent: an `NSControl` has one target, so give its
controls `track(_:)` (<doc:TrackingFromViews>).

### App lifecycle

The app's lifecycle can track itself too (module ``/LifecycleTracking``: every platform). Nothing
is tracked until the app turns it on as it launches, and keeps what that returns:

```swift
import LifecycleTracking

let store = try SegmentStore()  // every @Event, and the lifecycle's own events
let tracker = Tracker(store: store)
// In the application delegate's application(_:didFinishLaunchingWithOptions:), kept beside the tracker:
let lifecycle = tracker.trackLifecycle(
    kinds: [.installed, .updated, .opened, .backgrounded],
    versionStore: FileVersionStore(directory: store.directory)
)
let delivery = tracker.records
    .batch(strategy: .either(.count(20), .time(interval: .seconds(30), clock: ContinuousClock()), .lifecycle))
    .deliver(to: ConsoleDestination())
```

As it starts, it compares the app's version (`CFBundleShortVersionString`, or `version:`) with the
one its `VersionStore` saved at the last launch. No saved version tracks `ApplicationInstalled`; a
different one tracks `ApplicationUpdated(previousVersion:version:)`; the same one tracks neither.
The store keeps the version and nothing else. `FileVersionStore` keeps it in a file beside the
records, `InMemoryVersionStore` keeps it in memory for tests, and any type of yours can conform.

Then it tracks `ApplicationOpened(fromBackground: false)`. After that, from `UIApplication`'s,
`WKApplication`'s or `NSApplication`'s notifications, it tracks `ApplicationBackgrounded`,
`ApplicationOpened(fromBackground: true)` and, where the platform reports it,
`ApplicationTerminated`, each once per transition. A scene-based app gets one transition for the
whole app, not one per scene. On macOS, another app becoming active counts as the background.
`kinds:` turns kinds off. On Linux, a server or tool calls `await lifecycle.finish()` as it ends,
which tracks `ApplicationTerminated`.

As the app leaves the foreground, it waits for the tracker's worker to write every record tracked
so far to the store, then calls the store's `synchronize()`. A record accepted before the app went
to the background survives the app being killed there. A delivery batched with `.lifecycle` sends
what is pending as it reads the `ApplicationBackgrounded` record. The notification's handler only
hands the transition on: the work runs on a task of its own, never on the main thread, and on
platforms that suspend apps it holds background time from `ProcessInfo.performExpiringActivity`
until it is done.
