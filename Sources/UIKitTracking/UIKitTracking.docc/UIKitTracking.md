# ``UIKitTracking``

Hand UIKit views and view controllers their tracker as a trait, and track what controls do.

## Overview

Use this module to track events from UIKit views, view controllers and controls on iOS, iPadOS,
tvOS, visionOS and Mac Catalyst; elsewhere it builds empty, and on macOS and watchOS its API isn't
there. SwiftUI views use
[`SwiftUITracking`](https://tyler-keith-thompson.github.io/Traffluent/documentation/swiftuitracking),
and AppKit views on macOS use
[`AppKitTracking`](https://tyler-keith-thompson.github.io/Traffluent/documentation/appkittracking).

The tracker is a UIKit trait, `TrackerTrait`. Set it on a window scene's `traitOverrides` as the
scene connects, and every view controller and view in the scene's windows inherits it, the way
SwiftUI views inherit their environment. Read it in any of them as `traitCollection.tracker`. A
view controller or view can set its own for everything below it, and each scene keeps its own, so
two windows can track through two trackers. Until a tracker is set, the trait holds
`Tracker.noOp`, which drops every event.

`UIControl.track(_:for:)` tracks an event each time a control sends the given control events
(`.primaryActionTriggered` by default), through the tracker the control's traits hold at that
moment:

```swift
import UIKit

struct ShareTapped: Event {}

struct CheckoutStarted: Event {
    var cartSize: Int
}

final class CartViewController: UIViewController {
    let share = UIButton(configuration: .filled())
    let checkOut = UIButton(configuration: .filled())

    override func viewDidLoad() {
        super.viewDidLoad()
        share.track(ShareTapped())  // through the tracker the button's traits hold when it is tapped
        checkOut.addTarget(self, action: #selector(checkOut(_:)), for: .primaryActionTriggered)
        view.addSubview(share)
        view.addSubview(checkOut)
    }

    @objc func checkOut(_ sender: UIButton) {
        sender.traitCollection.tracker.track(CheckoutStarted(cartSize: 3))
    }
}

// In the scene delegate's scene(_:willConnectTo:options:):
windowScene.traitOverrides.tracker = tracker
```

`track(_:for:)` adds a `UIAction` beside the control's other actions and targets, so they still
run, and returns it; pass it to `removeAction(_:for:)` to stop tracking. Where SwiftUI hosts
UIKit, or UIKit hosts SwiftUI, the trait and SwiftUI's `\.tracker` are one value.

The guide
[Tracking from SwiftUI, UIKit and AppKit](https://tyler-keith-thompson.github.io/Traffluent/documentation/traffluent/trackingfromviews)
covers all three frameworks.

## API

This documentation is built on macOS, where the module is empty, so its symbols have no pages of
their own here. Their doc comments are in the sources, and Xcode shows them for an iOS target.

- `TrackerTrait`: the trait holding the tracker, `Tracker.noOp` until one is set.
- `UITraitCollection.tracker`: reads the trait.
- `UIMutableTraits.tracker`: sets the trait on a window scene's, view controller's or view's
  `traitOverrides`.
- `UIControl.track(_:for:)`: tracks an event each time the control sends the given control events.
