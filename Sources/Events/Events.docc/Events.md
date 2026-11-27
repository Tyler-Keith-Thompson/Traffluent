# ``Events``

The types every other module shares: the `Event` protocol, the values its properties can hold, and the record a tracker makes of each event.

## Overview

An event is a value that conforms to ``Event``, declared with `@Event`. Its stored properties
are its properties, so a misspelled or mistyped one is a compile error. Its type gives the name
destinations record it under, the ``ConsentCategory`` whose consent decides whether it is
delivered, and the version of its shape. Each has a default: the type's name,
``ConsentCategory/analytics`` and 1.

Two property types carry rules of their own. A ``Sensitive`` value, such as an email address,
prints as `<redacted>` and has no public accessor: a destination reads it through
``EventRecord/reveal(_:)``, which gives `nil` once a delivery has redacted the record. A
``Refined`` value satisfies every ``Constraint`` its ``Refinement`` lists, checked once as it is
made: its initializer throws ``UnsatisfiedConstraint`` for a value that breaks one. Each
``Constraint`` spelling throws ``InvalidConstraint`` for an argument no schema can hold, such as
a negative length.

A tracker (module `Trackers`) makes an ``EventRecord`` of each event it tracks: the event, its own
random identifier, when and where it was tracked, and the `ServiceContext` it was tracked in.
Destinations receive batches of these records. An ``Enricher`` adds to a record's context: a
tracker runs it on every record, or a destination's `enriched(by:)` on the records it receives.

Declare an event with `@Event` (module `EventMacros`, part of `import Traffluent`). It derives
the ``Event`` conformance from the struct's declaration and fills in its ``EventSchema``, and
`@Constrained` beside a property fills in ``Event/constraintViolation()``. To write the
conformance by hand instead, see ``Event``.

```swift
import Traffluent

enum PlanName: Refinement {
    static var constraints: [Constraint<String>] {
        get throws(InvalidConstraint) { try [.minLength(1), .maxLength(32)] }
    }
}

@Event(consent: .functional)
struct SignedUp {
    var plan: Refined<String, PlanName>
    var email: Sensitive<String>
}

let event = SignedUp(plan: try Refined("pro"), email: Sensitive("ada@example.com"))
let record = EventRecord(event: event, timestamp: .now, sourceLocation: nil)
let name = record.name  // "SignedUp"
let email = record.reveal(event.email)  // nil: a record made by hand keeps its sensitive values redacted
let empty = try? Refined<String, PlanName>("")  // nil: it throws UnsatisfiedConstraint.minLength
```

The umbrella guide on this area is
[Defining Events](https://tyler-keith-thompson.github.io/Traffluent/documentation/traffluent/definingevents).

## Topics

### Events

- ``Event``
- ``ConsentCategory``
- ``EventSchema``
- ``EventSchema/Enumeration``
- ``DiscoveredEvent``

### Property values

- ``Sensitive``
- ``Refined``
- ``Refinement``
- ``Constraint``
- ``ValidationKeyword``
- ``UnsatisfiedConstraint``
- ``InvalidConstraint``
- ``ConstraintViolation``

### Records

- ``EventRecord``
- ``SourceLocation``
- ``Enricher``

### Stores

- ``DeliveryTag``
- ``Acknowledger``
