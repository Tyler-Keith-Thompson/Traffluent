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
made: the plain initializer traps on a value that breaks one, and ``Refined/init(checked:)``
throws ``UnsatisfiedConstraint``.

A tracker (module `Trackers`) makes an ``EventRecord`` of each event it tracks: the event, its own
random identifier, when and where it was tracked, and the `ServiceContext` it was tracked in.
Destinations receive batches of these records.

Declare an event with `@Event` (module `EventMacros`, part of `import Traffluent`). It derives
the ``Event`` conformance from the struct's declaration and fills in its ``EventSchema``, and
`@Constrained` beside a property fills in ``Event/constraintViolation()``. To write the
conformance by hand instead, see ``Event``.

```swift
import Traffluent

enum PlanName: Refinement {
    static let constraints: [Constraint<String>] = [.minLength(1), .maxLength(32)]
}

@Event(consent: .functional)
struct SignedUp {
    var plan: Refined<String, PlanName>
    var email: Sensitive<String>
}

let event = SignedUp(plan: Refined("pro"), email: Sensitive("ada@example.com"))
let record = EventRecord(event: event, timestamp: .now, sourceLocation: nil)
let name = record.name  // "SignedUp"
let email = record.reveal(event.email)  // nil: a record made by hand keeps its sensitive values redacted
let empty = try? Refined<String, PlanName>(checked: "")  // nil: it throws UnsatisfiedConstraint.minLength
```

The umbrella guide on this area is
[Defining Events](https://tyler-keith-thompson.github.io/Traffluent/documentation/traffluent/definingevents).

## Topics

### Events

- ``Event``
- ``ConsentCategory``
- ``EventSchema``

### Property values

- ``Sensitive``
- ``Refined``
- ``Refinement``
- ``Constraint``
- ``ValidationKeyword``
- ``UnsatisfiedConstraint``
- ``ConstraintViolation``

### Records

- ``EventRecord``
- ``SourceLocation``

### Stores

- ``DeliveryTag``
- ``Acknowledger``
