# Tracking from SwiftUI, UIKit and AppKit

Give views the tracker the way each framework passes values down, and let modifiers and controls track what views do.

## Overview

None of these needs a global or swizzling. Each framework hands the tracker down its own view
hierarchy, so each scene or window can have a tracker of its own. In UIKit and AppKit the tracker is
found when an action fires, so a control moved to another window tracks through that window's
tracker.

### SwiftUI

On Apple platforms, views read the tracker from the environment (module ``/SwiftUITracking``,
empty elsewhere). Set it at the root of the views with `tracker(_:)`, read it in any view with
`@Environment(\.tracker)`, and let modifiers track what views do:

```swift
import SwiftUI

struct PlanSelected: Event {
    var plan: String
}

struct CheckoutView: View {
    @Environment(\.tracker) private var tracker
    @State private var plan = "free"

    var body: some View {
        Form {
            Picker("Plan", selection: $plan) {
                Text("Free").tag("free")
                Text("Pro").tag("pro")
            }
            .trackChange(of: plan) { PlanSelected(plan: $0) }
            Button("Sign up") {
                tracker.track(SignedUp(plan: plan))  // its record's context[ScreenKey.self] is "Checkout"
            }
        }
    }
}

let tracker = Tracker()
let root = CheckoutView()
    .trackScreen("Checkout")  // tracks ScreenViewed(screen: "Checkout") each time it appears
    .tracker(tracker)
```

Each modifier tracks through the environment's tracker, once per trigger, and records the place it
is applied as the call site:

- `trackOnAppear(_:)` tracks its event each time the view appears, as `onAppear` runs: again when a
  navigation stack pops back to it, but not when SwiftUI only redraws it.
- `trackOnTap(_:)` tracks each tap, beside the view's own action.
- `trackChange(of:_:)` tracks the event it makes from each new value, but not from the first value
  or an equal one.
- `trackScreen(_:)` tracks `ScreenViewed` each time the view appears. Inside the view, it puts a
  tracker enriched with the screen's `ScreenKey` in the environment, so the events tracked from the
  screen's actions and modifiers carry its name.

Apply `trackScreen(_:)` where the screen's view is placed, as above. A view's own `@Environment`
reads the environment around the view, which the modifiers in its own body don't change. Until a
tracker is set, the environment's tracker is `Tracker.noOp`, so a preview tracks nothing.

### UIKit

In UIKit (module ``/UIKitTracking``: iOS, iPadOS, tvOS, visionOS and Mac Catalyst), the tracker is
a trait. Set it on the window scene as it connects, and every view controller and view in the scene
inherits it, as SwiftUI views inherit their environment. Read it in an action with
`traitCollection.tracker`, or let `track(_:for:)` track a control's events:

```swift
import UIKit

struct ShareTapped: Event {}

final class CheckoutViewController: UIViewController {
    let share = UIButton(configuration: .filled())

    override func viewDidLoad() {
        super.viewDidLoad()
        share.track(ShareTapped())  // through the tracker the button's traits hold when it is tapped
        share.addTarget(self, action: #selector(signUp(_:)), for: .primaryActionTriggered)
        view.addSubview(share)
    }

    @objc func signUp(_ sender: UIButton) {
        sender.traitCollection.tracker.track(SignedUp(plan: "pro"))
    }
}

// In the scene delegate's scene(_:willConnectTo:options:):
windowScene.traitOverrides.tracker = tracker
```

A view controller can override the trait for the views below it, with a tracker `enriched(by:)` a
screen's name, say. `track(_:for:)` adds a `UIAction` beside the control's other actions and
returns it, for `removeAction(_:for:)`.

### AppKit

In AppKit (module ``/AppKitTracking``, macOS), a view finds its tracker the way an action finds its
target. `NSView.tracker` asks the view's responder chain (its superviews and view controllers, its
window and window controller), then the window's delegate and the application's delegate, for the
first one that conforms to `TrackerProviding`. `track(_:)` tracks an event each time a control
sends its action, just before the action:

```swift
import AppKit

final class CheckoutWindowController: NSWindowController, TrackerProviding {
    let tracker: Tracker

    init(window: NSWindow, tracker: Tracker) {
        self.tracker = tracker
        super.init(window: window)
    }

    required init?(coder: NSCoder) { nil }

    @objc func signUp(_ sender: NSButton) {
        sender.tracker.track(SignedUp(plan: "pro"))
    }
}

let share = NSButton(title: "Share", target: nil, action: nil)
share.track(ShareTapped())  // through the tracker of the window it is in when it is clicked
```

An `NSControl` has one target and action, so `track(_:)` puts its own in their place and sends the
control's action on to its target, or up the responder chain when it had none. Call it after
setting them.

### Mixing frameworks

SwiftUI's `\.tracker` and UIKit's trait are one value. SwiftUI views hosted in UIKit read the
scene's tracker, and UIKit views hosted in SwiftUI read the environment's.

To track screen views and control activations without a modifier or a call per control, see
<doc:AutomaticTracking>.
