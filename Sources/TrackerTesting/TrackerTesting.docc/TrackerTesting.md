# ``TrackerTesting``

Run a test's body with a fresh tracker and check the events it tracked, in order.

## Overview

`withRecordingTracker` makes a tracker, binds it to the current task with `withTracker` for the
length of its body, then finishes it and returns a ``TrackerRecording`` of every event tracked
through it. Each call makes its own tracker, so tests that run at once never see each other's
events. Events tracked after the body returns, by work it started but didn't wait for, are dropped.

There are four spellings. The body can be synchronous or asynchronous, and it can take the tracker
as a parameter, for code that is handed its tracker (a SwiftUI view given it with `tracker(_:)`, a
UIKit view controller given it as a trait) rather than reading `Tracker.current`.

A recording holds what the body returned, every record with its timestamp, source location and
context, each event's name, and the events of one type through ``TrackerRecording/events(of:)``.

Add the product to test targets only. To check a tracking plan from a test, use
`TrackingPlanTesting`.

```swift
import Testing
import TrackerTesting

@Test func checkingOutTracksTheCartSize() async {
    let tracked = await withRecordingTracker { tracker in
        tracker.track(CheckoutStarted(cartSize: 3))
        return "done"
    }
    #expect(tracked.value == "done")
    #expect(tracked.names == ["CheckoutStarted"])
    #expect(tracked.events(of: CheckoutStarted.self).map(\.cartSize) == [3])
}
```

The guide [Testing What Your Code Tracks](https://tyler-keith-thompson.github.io/Traffluent/documentation/traffluent/testingwhatyoutrack)
covers views, view controllers and asynchronous code.

## Topics

### Recording a body's events

- ``withRecordingTracker(_:)-8blfh``
- ``withRecordingTracker(_:)-mlec``
- ``withRecordingTracker(_:)-26pul``
- ``withRecordingTracker(_:)-pnmv``

### Reading what was tracked

- ``TrackerRecording``
