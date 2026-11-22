# ``Traffluent``

Vendor-neutral analytics for Swift: typed events delivered through a pipeline to any number of destinations.

## Overview

An event is a value conforming to `Event`. A `Pipeline` is a value holding destinations, and it delivers each event it tracks to every one of them. A `Destination` is a plain sink.

`import Traffluent` imports every module. Each module also has its own documentation and can be
imported on its own.

```swift
import Traffluent

struct SignedUp: Event {
    var plan: String
}

let pipeline = Pipeline(ConsoleDestination())
await pipeline.track(SignedUp(plan: "pro"))
```

## Topics

### Modules

- ``/Events``
- ``/Destinations``
- ``/Pipelines``
