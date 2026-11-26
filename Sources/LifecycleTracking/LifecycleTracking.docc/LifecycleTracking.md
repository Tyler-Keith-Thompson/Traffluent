# ``LifecycleTracking``

Track the app's installs, updates, opens, moves to the background and terminations, and make the
tracker's records durable as the app leaves the foreground.

## Overview

Use this module to track the application's lifecycle on any platform. Nothing is tracked until
the app calls `trackLifecycle` on its tracker as it launches, and keeps the
``LifecycleObservation`` it returns; tracking stops when that is cancelled, finished or released.
For the screens and controls inside the app, see
[Automatic Tracking](https://tyler-keith-thompson.github.io/Traffluent/documentation/traffluent/automatictracking).

As it starts, it compares the app's version (`CFBundleShortVersionString` by default, or
`version:`) with the one its ``VersionStore`` saved at the last launch. No saved version tracks
``ApplicationInstalled``, a different one ``ApplicationUpdated``, the same one neither. Then it
tracks ``ApplicationOpened``. After that, from `UIApplication`'s, `WKApplication`'s or
`NSApplication`'s notifications, it tracks ``ApplicationBackgrounded``, ``ApplicationOpened`` from
the background and, where the platform reports it, ``ApplicationTerminated``, each once per
transition. A server or a tool on Linux has no notifications, so it calls
``LifecycleObservation/finish()`` as it ends:

```swift
let tracker = Tracker()
let lifecycle = tracker.trackLifecycle(version: "2.1", versionStore: InMemoryVersionStore(version: "2.0"))
// tracks ApplicationUpdated(previousVersion: "2.0", version: "2.1"), then ApplicationOpened(fromBackground: false)

// ... the process's work ...

await lifecycle.finish()  // tracks ApplicationTerminated
await tracker.finish()
```

The store keeps the version and nothing else. ``FileVersionStore`` keeps it in a file, by default
beside a `SegmentStore`'s records; ``InMemoryVersionStore`` keeps it in memory, for tests; any type
of yours can conform. `kinds:` turns kinds of event off, while the version is still saved.

As the app leaves the foreground, it waits for the tracker's worker to write every record tracked
so far to the tracker's store, then calls the store's `synchronize()`. A delivery batched with
``LifecycleBatchStrategy`` (`.lifecycle`) sends what is pending as it reads the
``ApplicationBackgrounded`` record. The notification's handler only hands the transition on; the
work runs on a task of its own, and where the system suspends apps in the background it holds
background time until the records are durable.

## Topics

### Tracking the lifecycle

- ``Trackers/Tracker/trackLifecycle(kinds:version:versionStore:notificationCenter:file:fileID:function:line:column:)``
- ``LifecycleObservation``

### Events

- ``ApplicationInstalled``
- ``ApplicationUpdated``
- ``ApplicationOpened``
- ``ApplicationBackgrounded``
- ``ApplicationTerminated``

### Keeping the version

- ``VersionStore``
- ``FileVersionStore``
- ``InMemoryVersionStore``

### Delivering as the app leaves

- ``LifecycleBatchStrategy``
