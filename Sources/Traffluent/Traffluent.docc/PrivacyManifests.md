# Privacy Manifests

What each module can collect, the required-reason APIs it calls, and the privacy manifest it ships, so you can fill in your app's own manifest and privacy labels.

## Overview

Traffluent collects nothing on its own. It records only the events your app tracks and the
context your app turns on: every kind of automatic instrumentation and every standard enricher is
opt in. It sends records only to the destinations your app gives a delivery, to endpoints your app
names. None of it is used for tracking as Apple defines it: no module links what it records with
other companies' data, reads the advertising identifier, fingerprints the device, or works around
the user's consent or App Tracking Transparency. Every manifest declares `NSPrivacyTracking` as
`false` and lists no tracking domains.

Each module that can produce data of one of Apple's collected data types ships a
`PrivacyInfo.xcprivacy` declaring it. SwiftPM and Bazel both put it in a resource bundle named
`Traffluent_<Module>.bundle`, which Xcode and rules_apple copy into your app, where Xcode's privacy
report finds it. A module your app doesn't link adds nothing to the report.

### Required-reason APIs

No Traffluent module calls an API on Apple's list of required-reason APIs, so every manifest's
`NSPrivacyAccessedAPITypes` is empty. The list's categories are file timestamps
(`NSPrivacyAccessedAPICategoryFileTimestamp`), system boot time
(`NSPrivacyAccessedAPICategorySystemBootTime`), disk space
(`NSPrivacyAccessedAPICategoryDiskSpace`), active keyboards
(`NSPrivacyAccessedAPICategoryActiveKeyboards`) and user defaults
(`NSPrivacyAccessedAPICategoryUserDefaults`). The modules that come nearest:

| Module | What it calls | Why none is a required-reason API |
|---|---|---|
| ``/Persistence`` | swift-system's `FileDescriptor` (`open`, `read`, `write`, `seek`, `resize`, `close`), `fsync`, `unlink`, and `FileManager`'s `createDirectory`, `setAttributes` (the file protection class), `contentsOfDirectory` and `isExcludedFromBackup` | It reads no file's timestamps, size from `stat`, or the volume's free space: a segment's size is the offset `seek` returns at its end, and the store bounds itself by the bytes it has written. |
| ``/LifecycleTracking`` | `FileManager.fileExists`, `Data(contentsOf:)` and `Data.write(to:options:)` in `FileVersionStore`; `ProcessInfo.performExpiringActivity` | It reads and writes the version file's contents, never its attributes. |
| ``/StandardContext`` | `sysctlbyname` for `hw.machine` and `hw.model`, `ProcessInfo.operatingSystemVersion`, `Bundle.infoDictionary`, `Locale.current`, `NWPathMonitor`, `identifierForVendor` | None is on the list; `Enricher.vendorIdentifier()` is declared as collected data below. |
| ``/Sessions`` | The tracker's record timestamps (`Date`) | A session's inactivity is measured between records' wall-clock timestamps, not from the system's uptime. |
| ``/Trackers`` | `Date.now` | Wall-clock time, not boot time. |
| ``/Destinations`` | `ContinuousClock`, the default clock of `batch()` | The Swift runtime's clock, which isn't on the list. |
| ``/GRDBPersistence`` | GRDB | GRDB ships a privacy manifest of its own. |

Every other module calls nothing near the list. Of the packages Traffluent depends on,
swift-system's `Stat` API (`FilePath.stat()`, `FileDescriptor.stat()`) calls `stat`, `fstat`,
`lstat`, `fstatat` and `statfs`. Traffluent calls none of it. If your app does, your manifest
declares the file timestamp or disk space reason it needs.

### Collected data

Every declaration below is `NSPrivacyCollectedDataTypeLinked` `false` (Traffluent links nothing
to the user's identity), `NSPrivacyCollectedDataTypeTracking` `false`, and has the one purpose
`NSPrivacyCollectedDataTypePurposeAnalytics`. A module declares a type only when it makes data of
that type itself; it is collected only once your app turns the module on and delivers the records
off the device.

| Module | Data type | What it makes, once your app turns it on |
|---|---|---|
| ``/StandardContext`` | Device ID (`NSPrivacyCollectedDataTypeDeviceID`) | `Enricher.vendorIdentifier()`: the platform's `identifierForVendor`, as a `Sensitive` `VendorIdentifierKey`. |
| ``/StandardContext`` | Other Diagnostic Data (`NSPrivacyCollectedDataTypeOtherDiagnosticData`) | `Enricher.application()`, `device()`, `operatingSystem()` and `network()`: the app's bundle identifier, version and build; the device's model and form factor; the operating system's name and version; and the kind of network connection. |
| ``/StandardContext`` | Other Data Types (`NSPrivacyCollectedDataTypeOtherDataTypes`) | `Enricher.locale()`: the user's locale. |
| ``/SwiftUITracking`` | Product Interaction (`NSPrivacyCollectedDataTypeProductInteraction`) | `trackScreen(_:)`'s `ScreenViewed`, and the events `trackOnAppear(_:)`, `trackOnTap(_:)` and `trackChange(of:_:)` track as the user moves through the app. |
| ``/UIKitTracking`` | Product Interaction | The events `UIControl.track(_:for:)` tracks when a control's action fires. |
| ``/AppKitTracking`` | Product Interaction | The events `NSControl.track(_:)` tracks when a control sends its action. |
| ``/AutomaticScreenTracking`` | Product Interaction | `trackScreensAutomatically`: a `ScreenViewed` per screen, named after its view controller or SwiftUI view type. |
| ``/AutomaticControlTracking`` | Product Interaction | `trackControlsAutomatically`: a `ControlActivated` per touch that activates a control, named by its accessibility identifier, never its text. |
| ``/LifecycleTracking`` | Product Interaction | `trackLifecycle`: the app's installs, updates (with the versions), opens, moves to the background and terminations. |
| ``/Sessions`` | Product Interaction | `Enricher.sessions(timeout:kinds:)`: a random session identifier held in memory only, and `SessionStarted` and `SessionEnded` with the session's duration. |

The rest ship no manifest: ``/Events``, ``/Trackers``, ``/Persistence``, ``/GRDBPersistence``,
``/Checksums``, ``/Destinations``, ``/LoggingDestinations``, ``/TracingDestinations``,
``/HTTPDestinations``, ``/CollectorEncoding``, ``/PostHogEncoding``, ``/AmplitudeEncoding``,
``/MixpanelEncoding``, ``/PropertyJSON``, ``/JSONValues``, ``/EventMacros``, ``/TrackingPlans`` and
``/TrackingPlanTesting`` neither call a required-reason API nor make data of their own. They carry,
store and send the events and context your app and the modules above make.

### Your app's manifest and privacy labels

Traffluent's manifests cover what its modules make. Your app's manifest and its App Store privacy
labels also cover what your app adds:

- **Your events.** Each event type your app tracks is data your app collects: declare the type its
  properties hold (Product Interaction for taps and views, Purchase History for an order, and so
  on).
- **Your identifiers.** An identifier your app adds with an enricher of its own, such as an account
  identifier, is a User ID, linked to the user (<doc:IdentifyingPeople>).
- **Your destinations.** Where your destinations send records decides whether the data leaves the
  device, and whether a third party receives it. If an endpoint you send to uses the data for
  tracking, your app's manifest lists its domain under `NSPrivacyTrackingDomains`, and your app
  asks for permission through App Tracking Transparency first.
- **Modules you turn off.** If your app links a module but never turns it on, it collects nothing
  through it, and your privacy labels can leave that data out.
