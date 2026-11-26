# ``TrackingPlanTesting``

Fail a Swift Testing test when an app's events no longer match its committed tracking plan.

## Overview

``expectTrackingPlan(_:matches:sourceLocation:)`` checks a `TrackingPlan` against the plan
committed in a directory, as `TrackingPlan.check(againstDirectory:)` does. When they differ, it
records a Swift Testing issue whose comment is the check's report, the same text the `check`
command prints, and it returns the check either way. A plan that is only out of date fails the test
as a breaking one does: in both cases the committed plan isn't what exporting the events writes.

Add the product to an app's test target, so the check runs wherever the app's tests do. It imports
Swift Testing, so it belongs in test targets only. To run the check from the command line or CI
without a test, use the app's own `TrackingPlanCommand` executable from `TrackingPlans`.

```swift
import Foundation
import Testing
import TrackingPlanTesting

@Test func eventsMatchTheTrackingPlan() {
    let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("TrackingPlan")
    expectTrackingPlan(AppTrackingPlan.trackingPlan, matches: directory)
}
```

The guide [Exporting and Checking a Tracking Plan](https://tyler-keith-thompson.github.io/Traffluent/documentation/traffluent/trackingplanworkflow)
covers exporting the plan this test checks.

## Topics

### Checking from a test

- ``expectTrackingPlan(_:matches:sourceLocation:)``
