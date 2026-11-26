# ``AppKitTracking``

Let AppKit views find their tracker up the responder chain, and track what controls do.

## Overview

Use this module to track events from AppKit views and controls on macOS; elsewhere, Mac Catalyst
included, it builds empty. A Mac Catalyst app builds its views with UIKit, so it uses
[`UIKitTracking`](https://tyler-keith-thompson.github.io/Traffluent/documentation/uikittracking),
and SwiftUI views use
[`SwiftUITracking`](https://tyler-keith-thompson.github.io/Traffluent/documentation/swiftuitracking).

AppKit has no environment for views to inherit, so a view finds its tracker the way an action
sent to the first responder finds its target. ``AppKit/NSView/tracker`` asks the view's responder
chain (the view, its superviews and their view controllers, its window and window controller),
then the window's delegate and the application's delegate, and takes the tracker of the first one
that conforms to ``TrackerProviding``. It looks again each time it is read, so a view moved to
another window tracks through that window's tracker. A view below no provider gets `Tracker.noOp`,
which drops every event.

``AppKit/NSControl/track(_:file:fileID:function:line:column:)`` tracks an event each time a
control sends its action, just before the action:

```swift
import AppKit

struct ShareTapped: Event {}

struct CheckoutStarted: Event {
    var cartSize: Int
}

final class CartViewController: NSViewController, TrackerProviding {
    let tracker: Tracker

    init(tracker: Tracker) {
        self.tracker = tracker
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let share = NSButton(title: "Share", target: self, action: #selector(share(_:)))
        share.track(ShareTapped())  // after setting the target and action
        let checkOut = NSButton(title: "Check out", target: self, action: #selector(checkOut(_:)))
        view = NSStackView(views: [share, checkOut])
    }

    @objc func share(_ sender: NSButton) {}

    @objc func checkOut(_ sender: NSButton) {
        sender.tracker.track(CheckoutStarted(cartSize: 3))  // through this controller's tracker
    }
}
```

A control has one target and action, so `track(_:)` puts an object of its own in their place,
which tracks the event and then sends the control's action on to its target. Call it after
setting them; setting them afterwards replaces the tracking.

The guide
[Tracking from SwiftUI, UIKit and AppKit](https://tyler-keith-thompson.github.io/Traffluent/documentation/traffluent/trackingfromviews)
covers all three frameworks.

## Topics

### Finding the tracker

- ``TrackerProviding``
- ``AppKit/NSView/tracker``

### Tracking controls

- ``AppKit/NSControl/track(_:file:fileID:function:line:column:)``
