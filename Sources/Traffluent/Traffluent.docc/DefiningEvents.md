# Defining Events

Derive an event's conformances and schema from its declaration with `@Event`, and constrain which values its properties may hold.

## Overview

`@Event` (module ``/EventMacros``, part of `import Traffluent`) makes a struct an event from its
declaration, and is how you declare one. It adds the `Event` and `BinaryCodable`
conformances, the event's name, consent category and schema version when you give them, and a
`schema`, an `EventSchema` value that tooling reads:

```swift
import Traffluent

@Event(name: "checkout_started", version: 2)
struct CheckoutStarted {
    var cartSize: Int
    var coupon: String?
}

let tracker = Tracker()
tracker.track(CheckoutStarted(cartSize: 3, coupon: nil))
let properties = CheckoutStarted.schema.properties.map(\.name)  // ["cartSize", "coupon"]
```

The schema holds the name, the version, the consent category and each stored property's name, its
type as written, its optionality and whether it has a default value, in declaration order. The
encoding writes each of those properties under its name (<doc:PersistingRecords>), and a
`Sensitive` property keeps its redaction. The `Event` and `BinaryCodable` protocols' documentation
shows the same conformances written by hand. A record stored before a property with a default value
(`var currency: String = "USD"`) was added reads it as its default.

`version:` counts breaking changes only, and is 1 when left out; <doc:ChangingEvents> shows each
kind of change. `consent:` sets the event's `consentCategory` (`@Event(consent: .advertising)`).

A stored property whose type isn't `BinaryCodable` is a compile error that names it:
`static method 'requireBinaryCodable(position:)' requires that 'Coordinate' conform to 'BinaryCodable'`.
So are `@Event` on anything but a struct, and a stored property without a type annotation. Static
and computed properties are left out. The struct keeps its memberwise initializer.

### Constraining properties

A property's type says what kind of value it holds; a constraint says which values of that kind
are valid. A rule the type can enforce belongs in the type: a `Refined` value satisfies every
constraint of its `Refinement` from the moment it is made. Rules a plain `String` or `Int` can't
carry are declared beside the property with `@Constrained` (module ``/EventMacros``), and the
tracker checks them:

```swift
enum CouponCode: Refinement {
    static let constraints: [Constraint<String>] = [.pattern("^[A-Z0-9]{6}$", example: "SPRING")]
}

@Event(name: "search_performed")
struct SearchPerformed {
    @Constrained(.minLength(1), .maxLength(200))
    var query: String
    @Constrained(.minimum(0))
    var resultCount: Int
    var coupon: Refined<String, CouponCode>?
}

let coupon = try? Refined<String, CouponCode>(checked: "spring")  // nil: UnsatisfiedConstraint.pattern
let tracker = Tracker()
tracker.track(SearchPerformed(query: "", resultCount: 3, coupon: Refined("SPRING")))
await tracker.finish()
for await report in tracker.rejectionReports {
    print(report)  // search_performed: "query" breaks minLength 1 (1 rejected)
}
```

The keywords are JSON Schema's: `minLength` and `maxLength` (in Unicode scalars) and `pattern` for
a string, `minimum` and `maximum` for a number, `minItems` and `maxItems` for an array. Each is
offered only for the types it applies to, with its bound in the property's own type, so
`.minLength` on an `Int`, or `.minimum(0.5)` on an `Int`, is a compile error. In `@Constrained`,
so is a lower bound above its upper bound, a pattern that doesn't compile, and a pattern whose
`example` it, or another keyword of the property, rejects. In a `Refinement`, those trap when its
constraints are built. `Refined`'s plain initializer traps on a value that breaks its rule, as an
`Array` subscript does out of range; `init(checked:)` throws the `UnsatisfiedConstraint` instead.

### Rejected events

The tracker's worker checks each event's declared constraints before anything else, never on the
caller. An event that breaks one is rejected: never enriched, held by a consent, written to a store
or delivered. Each rejection is reported on `tracker.rejectionReports` as a `RejectionReport` naming
the event, the property and the keyword, and in debug builds it is logged at error level too.
Unread reports merge, one per event, property and keyword, counting the rejections and the range of
times they were tracked, so a broken call site in a loop can't fill memory.

A record that a store recovered from an earlier run is checked again, and the store forgets one
that a constraint added since rejects. A stored `Refined` value whose rule no longer accepts it
doesn't decode, and the store reports it. A `Sensitive` property takes no `@Constrained` keywords,
since checking one would reveal it; a `Sensitive<Refined<…>>` enforces its rule as it is made.

Both kinds of constraint are part of the event's schema. The exported tracking plan lists them
beside each property's type, and each example payload satisfies them, using a pattern's `example`
(<doc:TrackingPlanWorkflow>). An array's `Refined` elements are checked as they are made, but their
rules aren't exported.
