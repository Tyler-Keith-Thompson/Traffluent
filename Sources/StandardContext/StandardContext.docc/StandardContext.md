# ``StandardContext``

Stamp every event with the app, device, operating system, locale and network connection it was tracked on.

## Overview

Each standard value has an enricher of its own, and nothing is added to a record until the app
builds its tracker with that enricher. Each one sets a typed `ServiceContext` key whose value a
destination reads from the record's context: ``/Events/ApplicationKey``, ``/Events/DeviceKey``,
``/Events/OperatingSystemKey``, ``/Events/LocaleKey``, ``/Events/NetworkKey`` and
``VendorIdentifierKey``. The first five are in the `Events` module, as a store keeps them beside
each record, so a record recovered after a relaunch carries the values it was tracked with. This
module reads the values the platform reports.

The app, device, operating system and locale are read once, when the enricher is made, never per
event. The network connection changes while the app runs, so on Apple platforms `network()` starts
an `NWPathMonitor` of its own and sets the latest connection on each record. Give each tracker its
own call. Off Apple platforms there is no device and no path monitor, so those two enrichers set
nothing, and a server or tool, whose process usually has no Info.plist, passes its own app to
`application(_:)`.

`vendorIdentifier()`, made on the main actor, adds the platform's identifier for vendor as a
`Sensitive` value. It is the one identifier here that outlives a session, so add it only when the
app has decided to and has the user's consent. It is never stored or made up: on macOS and Linux,
which have none, records carry no key, and a store never writes it.

For the session an event was tracked in, use `Sessions`.

```swift
import StandardContext
import Trackers

let tracker = Tracker(enrichers: [.application(), .operatingSystem(), .locale(), .network()])
tracker.track(SignedUp(plan: "pro"))
// A destination reads each value from the record's context:
// record.context[ApplicationKey.self]?.version, record.context[OperatingSystemKey.self]?.name
```

The guide [Sessions and Standard Context](https://tyler-keith-thompson.github.io/Traffluent/documentation/traffluent/sessionsandstandardcontext)
covers each value and the identifier for vendor in more detail.

## Topics

### The app

- ``Events/Enricher/application(_:)``

### The device

- ``Events/Enricher/device(_:)``

### The operating system

- ``Events/Enricher/operatingSystem(_:)``

### The locale

- ``Events/Enricher/locale(_:)``

### The network connection

- ``Events/Enricher/network()``

### The identifier for vendor

- ``Events/Enricher/vendorIdentifier()``
- ``VendorIdentifierKey``
