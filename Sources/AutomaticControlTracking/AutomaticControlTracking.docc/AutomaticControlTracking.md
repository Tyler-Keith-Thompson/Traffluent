# ``AutomaticControlTracking``

Track a control activation each time a touch activates a UIKit control, without a call on each
control.

## Overview

Use this module when an app's UIKit controls should track their own activations, such as a button
tapped or a switch flipped. The discovery runs on iOS, iPadOS, tvOS, visionOS and Mac
Catalyst, through a `UIWindowScene`. ``ControlActivated``, the event it tracks, builds on every
platform, so a tracking plan or a server can name it. SwiftUI's controls are never tracked
automatically: give them `trackOnTap(_:)` from
[`SwiftUITracking`](https://tyler-keith-thompson.github.io/Traffluent/documentation/swiftuitracking).
macOS has no equivalent; give an `NSControl` `track(_:)` from
[`AppKitTracking`](https://tyler-keith-thompson.github.io/Traffluent/documentation/appkittracking).

Nothing is tracked until a window scene turns it on with `trackControlsAutomatically`. Each
control is named after its `accessibilityIdentifier`, never its title or other text, which may be
a person's data, and carries its kind, the first public UIKit class it is (`"UIButton"`). By
default a control without an identifier is skipped:

```swift
import UIKit

final class CartViewController: UIViewController {
    let checkOut = UIButton(configuration: .filled())

    override func viewDidLoad() {
        super.viewDidLoad()
        checkOut.accessibilityIdentifier = "checkout-button"  // tracked as ControlActivated(control: "checkout-button", kind: "UIButton")
        view.addSubview(checkOut)
    }
}

// In the scene delegate's scene(_:willConnectTo:options:), beside the scene's tracker:
windowScene.traitOverrides.tracker = tracker
windowScene.trackControlsAutomatically()
```

Give `trackControlsAutomatically` a closure to rename a control or skip it: it gets each
`DiscoveredControl`, with its identifier, kind and screen, and returns the event, or `nil`. Each
record's context carries the control's screen, the type of the view controller it is in, as
`ScreenKey`, unless the tracker's enrichers set one.

A touch that ends off the control tracks nothing, and neither do activations
without a touch, such as VoiceOver's, or actions the app sends itself with `sendActions(for:)`,
except to a control the last touch was on and didn't activate. Each activation goes
through the tracker the control's traits hold, so each scene keeps its own. The scene adds a
gesture recognizer to each of its windows that never recognizes, so it holds up no touch, and
swizzles nothing.

This documentation is built on macOS, so `UIWindowScene`'s `trackControlsAutomatically(_:)` and
`stopTrackingControlsAutomatically()`, and `DiscoveredControl`, have no pages here; their doc
comments are in the sources.

The guide
[Automatic Tracking](https://tyler-keith-thompson.github.io/Traffluent/documentation/traffluent/automatictracking)
also covers screen views and the app's lifecycle.

## Topics

### The event

- ``ControlActivated``
