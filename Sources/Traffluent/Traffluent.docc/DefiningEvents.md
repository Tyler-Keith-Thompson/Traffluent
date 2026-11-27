# Defining Events

Derive an event's conformances and schema from its declaration with `@Event`, and constrain which values its properties may hold.

## Overview

`@Event` (module ``/EventMacros``, part of `import Traffluent`) makes a struct an event from its
declaration, and is how you declare one. It adds the `Event`, `Encodable` and `Decodable`
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
`Codable` conformance writes each of those properties under its name (<doc:PersistingRecords>). An
optional's `nil` is left out, a `Date` property, or each date in a `[Date]` or `[Date?]`, is
written as the seconds since 2001 it holds, so it reads back exactly, and a `Sensitive` property
keeps its redaction. A `Date` the macro doesn't reach, inside a `Codable` type of your own or in an
event whose `Codable` conformance Swift synthesizes, takes the CBOR package's own form, seconds
since 1970, and reads back to within a rounding of a microsecond's scale. The `Event` protocol's documentation
shows the conformance written by hand. A record stored before a property with a default value
(`var currency: String = "USD"`) was added reads it as its default.

`version:` counts breaking changes only, and is 1 when left out; <doc:ChangingEvents> shows each
kind of change. `consent:` sets the event's `consentCategory` (`@Event(consent: .advertising)`).

A stored property whose type isn't `Codable` is a compile error that names it:
`static method 'requireCodable(position:)' requires that 'Coordinate' conform to 'Decodable'`.
So are `@Event` on anything but a struct, and a stored property without a type annotation. Static
and computed properties are left out. The struct keeps its memberwise initializer.

### Finding every event

You never list your events. `@Event` places a small record of the event in the compiled binary, and
`DiscoveredEvent.all` reads those records at run time: every `@Event` struct in the modules
linked into the program, the app's own and its packages', with each one's schema, ordered by name
and then version. On Apple platforms that includes the frameworks the app has loaded; "Limits"
below says what isn't found. The library's own events are in it too, once their modules are linked:
`SessionStarted` and `SessionEnded`, `ScreenViewed`, `ControlActivated` and the `Application`
events of `trackLifecycle`.

`SegmentStore()`, `DatabaseStore(database:)` and `TrackingPlan()` each take that list, so a new
event is stored and described as soon as it is declared. To keep only some events on disk, list them:
`SegmentStore(events: [SignedUp.self])` writes `SignedUp` alone, and any other event stays in
memory, delivered in this run and reported once as `notPersisted`. `TrackingPlan(schemas:)` takes
a list the same way.

An event that conforms to `Event` by hand, without `@Event`, has no record, so it isn't
discovered. Add it to the discovered ones where it is needed:
`SegmentStore(events: DiscoveredEvent.all.map(\.type) + [Legacy.self])` and
`TrackingPlan(schemas: DiscoveredEvent.all.map(\.schema) + [Legacy.schema])`. A generic `@Event`
struct, or one nested in a generic type's declaration, isn't discovered either, as a generic type
can't hold the record: the macro adds a note where it is declared, and you list it the same way.
An `@Event` struct declared in an extension of a generic type doesn't compile (`static stored
properties not supported in generic types`), as the macro can't tell from the extension that the
type is generic; declare it outside the generic type instead.

Event names must be unique across the program. Two discovered events of one name make
`SegmentStore()` and `DatabaseStore(database:)` throw `duplicateEventName`, as a store couldn't
tell their records apart, and two of one name and version make `TrackingPlan()` throw
`duplicateEvent`. Each error carries the name and both types' fully qualified names, such as
`duplicateEventName("signed_up", firstType: "AppTests.SignupTests.SignedUp", secondType:
"AppTests.CheckoutTests.SignedUp")`.

A test target is a program of its own, whose events are the ones it declares and links. A test
target whose fixtures reuse a name, two tests that each declare a `signed_up` event, gets that
error from `SegmentStore()` or `TrackingPlan()`. Either build the store or plan in the test from
an explicit list, `SegmentStore(events: [SignedUp.self])`, or rename one of the fixtures. A
tracking plan executable holds the events of the modules it links, so it links every module that
declares one (<doc:TrackingPlanWorkflow>).

#### Limits

- On Linux and the other ELF platforms, only the image that links the `Events` module is read,
  which is the whole program as SwiftPM and Bazel link Swift there. Events in a library loaded on
  its own, a dynamic library or a plugin, aren't found.
- An object file in a static archive that nothing references brings no record into the program,
  as the linker leaves it out: CocoaPods' static libraries, a static XCFramework, or a Bazel
  library with `alwayslink = False`. SwiftPM, and Bazel's `alwayslink = True`, link every object
  file.
- `DiscoveredEvent.all` holds the events of the images loaded when it is called. A framework
  loaded later adds its events from then on, so build the store and plan after it loads.
- Object formats other than Mach-O and ELF, COFF on Windows and WebAssembly's among them, find no
  events: `DiscoveredEvent.all` is empty, and Traffluent doesn't target them.

### Enum properties

A property can hold an enum whose raw value is a `String` or an integer type. Give the enum
`Codable`, which writes each case as its raw value:

```swift
@Event(name: "checkout_failed")
struct CheckoutFailed {
    enum Reason: String, Codable {
        case paymentDeclined
        case outOfStock = "out_of_stock"
    }
    var reason: Reason
}

let tracker = Tracker()
tracker.track(CheckoutFailed(reason: .outOfStock))  // stored as "out_of_stock"
let rawValues = CheckoutFailed.schema.properties[0].enumeration?.rawValues
// [.string("paymentDeclined"), .string("out_of_stock")]
```

The schema records the raw values in the property's `enumeration`, and the tracking plan exports
them as a JSON Schema `enum`, so a collector rejects any other value (<doc:TrackingPlanWorkflow>).
The macro lists the cases of an enum declared inside the event. Otherwise it reads them from
`allCases`, so an enum declared elsewhere needs `CaseIterable` for the plan to check its values.
The same goes for an enum inside the event with a case under `#if`, which the macro can't
evaluate. Without `CaseIterable`, the plan accepts any value for the property. A typealias of the
enum (`typealias Kind = Reason`) isn't matched either: the plan accepts any value for it, so
declare the property with the enum's own name. An enum declared inside the event must list
`Codable` in its inheritance clause. Adding the conformance in an extension doesn't count: the
macro sees only the struct, so it reports the enum as missing `Codable`.

A stored record whose raw value matches no case, such as one written before a case was renamed or
removed, doesn't decode, and the store drops and reports it (`DropReport.undecodable`). The plan
check reports such a change as breaking, so raise the event's version with it (<doc:ChangingEvents>).

### Constraining properties

A property's type says what kind of value it holds; a constraint says which values of that kind
are valid. A rule the type can enforce belongs in the type: a `Refined` value satisfies every
constraint of its `Refinement` from the moment it is made. Rules a plain `String` or `Int` can't
carry are declared beside the property with `@Constrained` (module ``/EventMacros``), and the
tracker checks them:

```swift
enum CouponCode: Refinement {
    static var constraints: [Constraint<String>] {
        get throws(InvalidConstraint) { try [.pattern("^[A-Z0-9]{6}$", example: "SPRING")] }
    }
}

@Event(name: "search_performed")
struct SearchPerformed {
    @Constrained(.minLength(1), .maxLength(200))
    var query: String
    @Constrained(.minimum(0))
    var resultCount: Int
    var coupon: Refined<String, CouponCode>?
}

let coupon = try? Refined<String, CouponCode>("spring")  // nil: UnsatisfiedConstraint.pattern
let tracker = Tracker()
tracker.track(SearchPerformed(query: "", resultCount: 3, coupon: try Refined("SPRING")))
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
`example` it, or another keyword of the property, rejects. Built at run time, as a `Refinement`'s
are, a constraint with an argument no JSON Schema could state (a negative length, a bound that
isn't finite, a pattern that doesn't compile or doesn't match its example) throws
`InvalidConstraint`. `Refined`'s initializer throws the `UnsatisfiedConstraint` of the first
constraint a value breaks, or `invalidConstraint` when the rule's constraints throw.

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
