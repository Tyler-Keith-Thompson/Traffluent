# ``Traffluent``

Vendor-neutral analytics for Swift: typed events delivered through a pipeline to any number of destinations.

## Overview

An event is a value conforming to `Event`. A `Pipeline` is a value holding destinations. Tracking an event records it as an `EventRecord`, with its timestamp and the caller's `SourceLocation`; running the pipeline gathers the records into batches by a batching strategy and delivers each batch to every destination. A `Destination` is a plain sink.

`import Traffluent` imports every module. Each module also has its own documentation and can be
imported on its own.

```swift
import Traffluent

struct SignedUp: Event {
    var plan: String
}

let pipeline = Pipeline(ConsoleDestination())
pipeline.track(SignedUp(plan: "pro"))
pipeline.finish()
try await pipeline.run().execute()
```

## Topics

### Modules

- ``/Events``
- ``/Destinations``
- ``/Pipelines``
