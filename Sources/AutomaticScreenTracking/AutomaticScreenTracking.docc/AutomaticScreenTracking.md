# ``AutomaticScreenTracking``

Track a screen view each time a screen's view controller appears, without a modifier or a call on
each screen.

## Overview

Use this module when an app's screens should track their own views: on iOS, iPadOS, tvOS,
visionOS and Mac Catalyst through a `UIWindowScene`, and on macOS through an `NSWindow`. On
watchOS and Linux it builds empty. To track one screen by hand, or a view a macOS
`NavigationStack` pushes, give it `trackScreen(_:)` from
[`SwiftUITracking`](https://tyler-keith-thompson.github.io/Traffluent/documentation/swiftuitracking)
instead.

Nothing is tracked until a window scene or a window turns it on with `trackScreensAutomatically`.
A screen is a view controller on screen none of whose children is: the one a navigation
controller shows, a tab's, one presented. It tracks `ScreenViewed` once as it appears, and again
when it reappears after being covered or hidden. The screen is named after its controller's type,
or for a hosting controller after the type of the SwiftUI view it shows. The closure gets each
``DiscoveredScreen`` and returns the event to track, renamed, or `nil` to skip the screen:

```swift
// In the scene delegate's scene(_:willConnectTo:options:), beside the scene's tracker:
windowScene.traitOverrides.tracker = tracker
windowScene.trackScreensAutomatically { screen in
    screen.name == "DebugMenuViewController" ? nil : ScreenViewed(screen: screen.name)
}
```

On macOS, a window turns it on, and each screen view goes through the tracker the screen's view
finds up its responder chain (`NSView.tracker`, from
[`AppKitTracking`](https://tyler-keith-thompson.github.io/Traffluent/documentation/appkittracking)):

```swift
import AppKit
import SwiftUI

struct PreferencesView: View {
    var body: some View {
        Text("Preferences")
    }
}

final class PreferencesWindowController: NSWindowController, TrackerProviding {
    let tracker: Tracker

    init(tracker: Tracker) {
        self.tracker = tracker
        super.init(window: NSWindow(contentViewController: NSHostingController(rootView: PreferencesView())))
    }

    required init?(coder: NSCoder) { nil }
}

let controller = PreferencesWindowController(tracker: tracker)
controller.window?.trackScreensAutomatically()  // tracks ScreenViewed(screen: "PreferencesView")
controller.showWindow(nil)
```

`kinds:` limits tracking to UIKit's (or AppKit's) view controllers or to SwiftUI's views. A
SwiftUI screen given `trackScreen(_:)` is left to that modifier, so it isn't tracked twice.
Discovery looks after each turn of the main run loop, swizzles nothing, and touches no other scene
or window. On a UIKit platform, each screen view goes through the tracker the screen's traits
hold, so each scene keeps its own.

This documentation is built on macOS, so `UIWindowScene`'s `trackScreensAutomatically(kinds:_:)`
and `stopTrackingScreensAutomatically()` have no pages here; they take the same parameters as
`NSWindow`'s, with `kinds:` defaulting to `[.uiKit, .swiftUI]`, and their doc comments are in the
sources.

The guide
[Automatic Tracking](https://tyler-keith-thompson.github.io/Traffluent/documentation/traffluent/automatictracking)
also covers control activations and the app's lifecycle.

## Topics

### Tracking a window's screens

- ``AppKit/NSWindow/trackScreensAutomatically(kinds:file:fileID:function:line:column:_:)``
- ``AppKit/NSWindow/stopTrackingScreensAutomatically()``

### Naming screens

- ``DiscoveredScreen``
- ``DiscoveredScreen/Kind``
