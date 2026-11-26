# ``EventMacros``

Derive an event's conformances, name and schema from its struct declaration, and declare the constraints its properties satisfy.

## Overview

`@Event` makes a struct an event. It adds the `Event` and `BinaryCodable` conformances, the
event's name, consent category and schema version when you give them, a `schema` describing each
stored property in declaration order, and an encoding that writes each stored property under its
name. `@Constrained` declares rules a plain `String`, number or array can't carry, such as a
minimum length or a pattern; the macro checks each keyword as it expands, and a tracker rejects an
event whose property breaks one.

The module is a product of its own that `import Traffluent` leaves out, so only apps that use it
build swift-syntax. It re-exports `Events` and `Persistence`, so a file that imports `EventMacros`
alone can expand the macro. To write an event's conformances by hand, conform to `Event` and
`BinaryCodable` from those modules without this one. To export the schemas as a JSON Schema
tracking plan, pass them to `TrackingPlans`.

```swift
import EventMacros

@Event(name: "search_performed", consent: .functional, version: 2)
struct SearchPerformed {
    @Constrained(.minLength(1), .maxLength(200))
    var query: String
    var resultCount: Int
    var filter: String?
}

let names = SearchPerformed.schema.properties.map(\.name)  // ["query", "resultCount", "filter"]
```

Raise `version:` only for a change that records stored at the earlier version can't be read
through; a store drops those records rather than reading them as the new shape.

The guide [Defining Events](https://tyler-keith-thompson.github.io/Traffluent/documentation/traffluent/definingevents)
covers both macros, and
[Changing Events](https://tyler-keith-thompson.github.io/Traffluent/documentation/traffluent/changingevents)
shows which changes need a new version.

## Topics

### Defining an event

- ``Event(name:consent:version:)``

### Constraining properties

- ``Constrained(_:)``
