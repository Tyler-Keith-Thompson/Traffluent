# ``StandardContext``

Stamp every event with the app, device, operating system, locale and network connection it was tracked on.

## Overview

Each standard value has an enricher of its own, and nothing is added to a record until the app
builds its tracker with that enricher. Each one sets a typed `ServiceContext` key whose value a
destination reads from the record's context: ``ApplicationKey``, ``DeviceKey``,
``OperatingSystemKey``, ``LocaleKey``, ``NetworkKey`` and ``VendorIdentifierKey``.

The app, device, operating system and locale are read once, when the enricher is made, never per
event. The network connection changes while the app runs, so on Apple platforms `network()` starts
an `NWPathMonitor` of its own and sets the latest connection on each record. Give each tracker its
own call. Off Apple platforms there is no device and no path monitor, so those two enrichers set
nothing, and a server or tool, whose process usually has no Info.plist, passes its own app to
`application(_:)`.

`vendorIdentifier()`, made on the main actor, adds the platform's identifier for vendor as a
`Sensitive` value. It is the one identifier here that outlives a session, so add it only when the
app has decided to and has the user's consent. It is never stored or made up: on macOS and Linux,
which have none, records carry no key.

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
- ``ApplicationKey``

### The device

- ``Events/Enricher/device(_:)``
- ``DeviceKey``

### The operating system

- ``Events/Enricher/operatingSystem(_:)``
- ``OperatingSystemKey``

### The locale

- ``Events/Enricher/locale(_:)``
- ``LocaleKey``

### The network connection

- ``Events/Enricher/network()``
- ``NetworkKey``

### The identifier for vendor

- ``Events/Enricher/vendorIdentifier()``
- ``VendorIdentifierKey``
