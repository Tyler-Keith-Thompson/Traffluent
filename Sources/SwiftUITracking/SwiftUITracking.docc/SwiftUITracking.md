# ``SwiftUITracking``

Give SwiftUI views a tracker through the environment, and track what they do with view modifiers.

## Overview

Use this module to track events from SwiftUI views on Apple platforms; elsewhere it builds empty.
Set a tracker once, at the root of the views, with `tracker(_:)`, and read it in any view below
with `@Environment(\.tracker)`. A button's action can track through it, which a `withTracker`
binding can't reach, since SwiftUI runs actions on tasks of its own. Until a tracker is set, the
environment holds `Tracker.noOp`, so a preview tracks nothing.

The modifiers track through the environment's tracker, once per trigger, and record the place
they are applied as the call site. `trackOnAppear(_:)` tracks each time a view appears,
`trackOnTap(_:)` each tap beside the view's own action, and `trackChange(of:_:)` each new value.
`trackScreen(_:)` tracks ``ScreenViewed`` each time the view appears, and puts a tracker enriched
with the screen's ``ScreenKey`` in the environment inside it, so every event tracked from the
screen carries its name:

```swift
import SwiftUI

struct CartOpened: Event {}

struct CheckoutStarted: Event {
    var cartSize: Int
}

struct CartView: View {
    @Environment(\.tracker) private var tracker

    var body: some View {
        List {
            Button("Check out") {
                tracker.track(CheckoutStarted(cartSize: 3))  // its record's context[ScreenKey.self] is "Cart"
            }
        }
        .trackOnAppear(CartOpened())
    }
}

let tracker = Tracker()
let root = CartView()
    .trackScreen("Cart")  // tracks ScreenViewed(screen: "Cart") each time it appears
    .tracker(tracker)
```

Apply `trackScreen(_:)` where the screen's view is placed, as above, not in the view's own `body`:
a view's `@Environment` reads the environment around it, which its own body's modifiers don't
change.

Where UIKit has traits, the environment's tracker is the same value as UIKit's trait
(``/UIKitTracking``), so SwiftUI views hosted in UIKit read the scene's tracker. For UIKit and
AppKit views, see ``/UIKitTracking`` and
[`AppKitTracking`](https://tyler-keith-thompson.github.io/Traffluent/documentation/appkittracking).
To track screens without a modifier on each, see
[`AutomaticScreenTracking`](https://tyler-keith-thompson.github.io/Traffluent/documentation/automaticscreentracking).
The guide
[Tracking from SwiftUI, UIKit and AppKit](https://tyler-keith-thompson.github.io/Traffluent/documentation/traffluent/trackingfromviews)
covers all three frameworks.

## Topics

### Setting the tracker

- ``SwiftUICore/EnvironmentValues/tracker``
- ``SwiftUICore/View/tracker(_:)``

### Tracking from views

- ``SwiftUICore/View/trackOnAppear(_:file:fileID:function:line:column:)``
- ``SwiftUICore/View/trackOnTap(_:file:fileID:function:line:column:)``
- ``SwiftUICore/View/trackChange(of:_:file:fileID:function:line:column:)``

### Screens

- ``SwiftUICore/View/trackScreen(_:file:fileID:function:line:column:)``
- ``ScreenViewed``
- ``ScreenKey``
