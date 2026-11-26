# Testing What Your Code Tracks

Run a test's body with a fresh tracker and check the events it tracked.

## Overview

Add the ``/TrackerTesting`` product to the test target. `withRecordingTracker` binds a fresh
tracker to the test's task for the length of its body, then returns every event tracked in it, in
order. Here `SignedUp` is `Equatable`:

```swift
import Testing
import TrackerTesting

@Test func signingUpTracksThePlan() async {
    let tracked = await withRecordingTracker {
        Tracker.current.track(SignedUp(plan: "pro"))
    }
    #expect(tracked.events(of: SignedUp.self) == [SignedUp(plan: "pro")])
}
```

Each call has a tracker of its own, so tests running at the same time never see each other's
events. The body may be sync or async, and may return a value, read as `tracked.value`.
`tracked.names` lists every event's name and `tracked.records` every record.

Most code needs nothing more: it tracks through `Tracker.current`, which falls back to the tracker
the app bootstrapped, and the test's binding wins over that one. Pass a tracker instead where the
code reads one set for a single view tree. A tracker given to a SwiftUI view with `tracker(_:)`, such as a preview's,
reaches the view's environment but not code that reads `Tracker.current`. Such a test takes the
tracker the body is given and sets it on the view: `withRecordingTracker { tracker in … }`.
