# Sessions and Standard Context

Stamp every event with its session and with the app, device, system, locale and network it was tracked on.

## Overview

Sessions and standard context are enrichers: nothing is added to an event until the app builds its
tracker with them.

Give these enrichers to the tracker. It runs them on its worker for every event, and every
destination sees what they set. A destination's `enriched(by:)` is for values about that
destination or the delivery, such as a region or a deployment tag, not about the event
(<doc:ChoosingDestinations>). It runs when the batch is delivered, so a record a store recovered
after a relaunch would get this run's app version and operating system, and the network at upload
time. Keep `.sessions()` on the tracker too: at a destination, the `SessionStarted` and
`SessionEnded` events it adds are left out.

### Sessions

Every event can carry the session it was tracked in (module ``/Sessions``: every platform). Nothing
is put in a session until the app adds the sessions enricher to the ones it builds its tracker with:

```swift
import Sessions

let tracker = Tracker(enrichers: [.sessions(timeout: .seconds(30 * 60))])
tracker.track(SignedUp(plan: "pro"))  // its record's context[SessionKey.self] is the session's UUID
```

The tracker's worker sets each record's `SessionKey` to its session's identifier, through every
copy of the tracker, the environment's and the traits' included. A session goes on while each event
comes less than the timeout (30 minutes by default) after the one before it. The gap is measured
between the events' timestamps, when each was tracked. The first event after a longer gap starts a
new session. So when the app comes back from the background past the timeout, its first event, such
as `ApplicationOpened`, starts a new session, without ``/Sessions`` and ``/LifecycleTracking``
knowing about each other.

`SessionStarted` comes before each session's first event, at its time. From the second session on,
`SessionEnded(duration:)` comes before that, stamped with the time of the ended session's last
event, its duration running from the session's first event to its last. A session ends only when an
event comes after the timeout, so a run's last session has no `SessionEnded`; a destination takes
its end from its last event. `kinds:` turns either event off, or both, and every record still
carries its session's key.

The identifier is a version 7 UUID: its first 48 bits are the session's start in Unix milliseconds,
which every record's timestamp sends anyway, and the rest is random, derived from nothing. It lives
in the enricher's memory only.
Neither the tracker nor its store writes it to disk (a store keeps no record's context), and the
next launch's tracker starts a new session with a new identifier. Traffluent keeps no identifier
that links one session to another.

### Standard context

Every event can carry what most analytics want beside it: the app, the device, the operating
system, the locale and the network connection (module ``/StandardContext``: every platform). Each
is an enricher of its own, so nothing is added until the app adds it:

```swift
import StandardContext

let tracker = Tracker(enrichers: [.application(), .device(), .operatingSystem(), .locale(), .network()])
tracker.track(SignedUp(plan: "pro"))  // its record's context[OperatingSystemKey.self]?.name is "iOS" on an iPhone
```

Each sets a typed key whose value is a small struct a destination reads from each record's context:

| Key | Holds |
|---|---|
| `ApplicationKey` | Bundle identifier, version and build |
| `DeviceKey` | Model identifier and form factor |
| `OperatingSystemKey` | Name and version |
| `LocaleKey` | A `Locale`, with its identifier, language and region |
| `NetworkKey` | Wi-Fi, cellular, wired Ethernet, another kind, or offline |

The app, device, system and locale are read once, as the enricher is made, never per event. The
network connection changes, so its enricher starts an `NWPathMonitor` of its own, which stops when
the last tracker holding the enricher goes away, and sets the latest connection on each event.

Off Apple platforms there is no device and no path monitor, so those enrichers set nothing. A
process there usually has no Info.plist either, so a server or tool passes its own app:

```swift
let tracker = Tracker(enrichers: [
    .application(ApplicationKey.Value(bundleIdentifier: "com.example.server", version: "1.2.0", build: "42")),
    .operatingSystem(),
])
```

### The identifier for vendor

`.vendorIdentifier()`, made on the main actor, adds the platform's `identifierForVendor` as
`VendorIdentifierKey`. The operating system owns it, gives the same one to every app of one vendor
on the device, and resets it once they are all removed. Of the identifiers Traffluent offers, it is
the only one that outlives a session. No record carries it unless the app adds the enricher, and the
app owns that decision and the user's consent to it. Traffluent never writes it to disk or makes one
up: on macOS and Linux, which have none, records carry no key. It is a `Sensitive` value, so a
destination given `redactingSensitiveValues()` never receives it (<doc:ChoosingDestinations>).
<doc:IdentifyingPeople> covers identifiers that outlive a session.
