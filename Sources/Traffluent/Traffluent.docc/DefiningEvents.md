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

### Main-actor isolation

The conformance `@Event` adds is `nonisolated`, because the tracker encodes events off the main
actor. `@Event` works in an app target whose default isolation is the main actor
(`-default-isolation MainActor`, the default for a new app target in Xcode 26 and later), and on a
struct marked `@MainActor`.

A struct marked `@MainActor` (or another global actor) can hold only `Sendable` stored properties:
Swift lets nonisolated code, the event's coding and schema included, read a stored property of a
main-actor struct only when its type is `Sendable`. A property of a non-`Sendable` type fails to
compile inside the expansion (`cannot form key path to main actor-isolated property`); make the
type `Sendable`, or drop `@MainActor` from the event.

In a target whose default isolation is the main actor, a `Codable` type of your own that an event
holds is main-actor isolated too, and so is its `Codable` conformance, which the event's coding
can't use. The error reads
`main actor-isolated conformance of 'Coordinate' to 'Decodable' cannot be used in nonisolated context`.
Declare the type `nonisolated` (`nonisolated struct Coordinate: Codable`). An enum with a raw
value needs nothing, as its coding comes from the standard library.

### Finding every event

You never list your events. `@Event` places a small record of the event in the compiled binary, and
`DiscoveredEvent.all` reads those records at run time: every `@Event` struct in the modules
linked into the program, the app's own and its packages', with each one's schema, ordered by name
and then version. That includes the frameworks and dynamic libraries the app has loaded;
"Limits" below says what isn't found. The library's own events are in it too, once their modules
are linked: `SessionStarted` and `SessionEnded`, `ScreenViewed`, `ControlActivated` and the
`Application` events of `trackLifecycle`.

`SegmentStore()`, `DatabaseStore(database:)` and `TrackingPlan()` each take that list, so a new
event is stored and described as soon as it is declared. To keep only some events on disk, list them:
`SegmentStore(events: [SignedUp.self])` writes `SignedUp` alone, and any other event stays in
memory, delivered in this run and reported once as `notPersisted`. `TrackingPlan(schemas:)` takes
a list the same way.

An event that conforms to `Event` by hand, without `@Event`, has no record, so it isn't
discovered. Add it to the discovered ones where it is needed:
`SegmentStore(events: DiscoveredEvent.all.map(\.type) + [Legacy.self])` and
`TrackingPlan(schemas: DiscoveredEvent.all.map(\.schema) + [Legacy.schema])`. A generic `@Event`
struct, or one nested in a generic type's declaration, isn't discovered either, as a record holds
one concrete type: the macro adds a note where it is declared, and you list it the same way.
An `@Event` struct in an extension that shows the type is generic, by naming its arguments
(`extension Box<Int>`, `extension [Int]`) or with a `where` clause, gets the same note. In a plain
`extension Box` of a generic type it doesn't compile (`static stored properties not supported in
generic types`), as the macro can't tell from the extension that the type is generic; declare it
outside the generic type instead.

Event names must be unique across the program, whatever their versions: the build checks the name
alone, and a store built from a list takes one type per name. Within one executable or library,
the build checks this. Beside each event's record, `@Event` declares a function whose symbol is
named for the event's name, so a second event of that name defines the symbol again. In one
module the compiler refuses it (`multiple definitions of symbol`). Across the modules linked into
one executable or library, the linker refuses it, naming the symbol and both object files:

```
duplicate symbol '_$linkerset_kind_65766E74_key_OrderPlaced' in:
    .../libCheckout.a[2](OrderPlaced.swift.o)
    .../libOrders.a[2](OrderPlaced.swift.o)
```

The symbol is `$linkerset_kind_65766E74_key_` followed by the name, with ASCII letters and digits
kept and every other byte written as `_` and two hex digits, so `signed_up` reads `signed_5Fup`. The
name is the one `name:` gives, or the type's name without it. `@Event` declares that name as the
event's `name` itself, so the name can't differ from the one the build checks: a struct that
declares a static `name` of its own is a compile error, with a Fix-It that moves a string literal
into `@Event(name:)`, and a `name` declared in an extension or under `#if` is a redeclaration the
compiler refuses.

The library's own events are checked the same way, so their names are taken in a program that
links their modules: `SessionStarted` and `SessionEnded` (`Sessions`), `ScreenViewed`
(`SwiftUITracking`), `ControlActivated` (`AutomaticControlTracking`), and `ApplicationInstalled`,
`ApplicationUpdated`, `ApplicationOpened`, `ApplicationBackgrounded` and `ApplicationTerminated`
(`LifecycleTracking`). An app's `@Event struct SessionStarted`, or any event that `name:` gives one
of these names, fails to link beside that module; give it another name.

The build can't compare names across separate images, so the stores and the plan check again when
they read the events. Two discovered events of one name and version make `SegmentStore()` and
`DatabaseStore(database:)` throw `duplicateEventName`, and `TrackingPlan()` throw
`duplicateEvent`. Each error carries the name and both types' fully
qualified names, such as `duplicateEventName("signed_up", firstType: "Checkout.SignedUp",
secondType: "Signup.SignedUp")`. "Limits" below lists the cases only these errors catch.

A test target is a program of its own, whose events are the ones it declares and links. A test
target whose fixtures reuse a name, two tests that each declare a `signed_up` event, fails to
build. Rename one of the fixtures, or declare them inside a `private` or `fileprivate` type, such
as a private test suite: the build doesn't check names there (see "Limits"). The target then holds
two events of one name, so `SegmentStore()` and `TrackingPlan()` throw in it when the two share a
version; build the store or plan in such a test from an explicit list,
`SegmentStore(events: [SignedUp.self])`. A unit test bundle that Xcode hosts in the app is an
image of its own, apart from the app's, so a fixture there that shares an app event's name isn't
refused by the build, only by a store or plan that reads both, when the two share a version. A
tracking plan executable holds the events of the modules it links, so it links every module that
declares one (<doc:TrackingPlanWorkflow>).

A program that needs several versions of one event as types at once, such as a relay that reads
records sent at an older version, declares the older ones inside a `private` type, where the
build doesn't check their names. `TrackingPlan()` and a `CollectorBatchDecoder` take one type per
name and version, so they hold every version. `SegmentStore()` and `DatabaseStore(database:)`
keep only the highest version of each name, the one the program tracks
(<doc:PersistingRecords>). An explicit list, `SegmentStore(events:)`, still takes one type per
name, whatever its version. Declare that private type at file scope, or `fileprivate` inside
another type. `@Event` conforms the type in an extension at file scope, which can't see a type
that is a `private` member of another, so the macro reports an event in one as an error and says
which type to make `fileprivate`.

#### Limits

- An event's record is in the program only if its object file is, and a linker that reads a
  static archive on demand takes only the members something references
  ([Platforms and linking](https://tyler-keith-thompson.github.io/LinkerSets/documentation/linkersets/platformsandlinking)
  says when). This holds for the library's own events too: each sits in a file of its own, and an
  app on a Mac or Linux that links AutomaticControlTracking may never refer to `ControlActivated`.
  SwiftPM and Bazel link the event modules whole, Traffluent's included: SwiftPM links every
  object file of a program's modules, `swift_library` is `alwayslink = True` unless a target says
  otherwise, and rules_swift_package_manager sets it on every target of a package. With `-ObjC`,
  Apple's linker also loads each member that declares a Swift type, and every `@Event` declares a
  struct. Other builds leave such files out: a static library or static XCFramework linked without
  `-ObjC`, or a Bazel target set to `alwayslink = False` on Linux. To have such a library's events
  found, link it whole: `-force_load` on Apple platforms, `--whole-archive` on Linux, or
  `alwayslink = True` on its Bazel target.
- `DiscoveredEvent.all` holds the events of the images loaded when it is called: the program and
  the dynamic libraries and frameworks it links. A library or plug-in opened later with `dlopen`
  adds its events from then on, so build the store and plan after it loads.
- A library that loads or unloads while `DiscoveredEvent.all` runs is either read whole or left
  out of that call. On Apple platforms one that dyld adds before the read starts is found; on Linux
  a `dlopen` or `dlclose` waits for the read to finish, so the library is missed. The next call
  sees the change.
- Don't `dlclose` a library that declares events while the app runs. On Apple platforms dyld keeps
  it mapped, so its events are still found. On Linux the loader unmaps it while the Swift runtime
  keeps its types registered, and the process can crash later. Open plug-ins once and keep them
  open, or open them with `RTLD_NODELETE`.
- A module that declares events, linked into two images (a framework and the app, each holding a
  static copy), lists each of its events twice, and stores and plans refuse the duplicate. Link
  each such module into one image.
- The build's check of names covers one linked image: the modules linked statically into one
  executable or one library. A dynamic library or framework keeps its symbols apart from the app's,
  an image opened with `dlopen` is never compared with the program, and a module linked into two
  images has a copy of each symbol in each, so the build passes all three. The run-time errors
  above catch them, when a store or plan reads the events.
- With Apple's linker, a duplicate name in a static archive that the linker reads on demand is
  only a warning (`ld: warning: duplicate symbol`) when `-dead_strip` is on, as Xcode turns it on
  by default, and the app links. This is LinkerSets' account of the linker, untested here. Link
  such an archive whole (`-force_load`), or pass `-Xlinker -fatal_warnings`, to keep it an error.
  SwiftPM, and Bazel for a `swift_library` left at `alwayslink = True`, link every object file,
  and there a duplicate is an error.
- An event declared inside a `private` type at file scope, a `fileprivate` type, or an extension
  marked either way, isn't checked by the build: the symbol would be local to its file, and the
  linker never compares local symbols. Stores and plans still refuse its name at run time when it
  shares a version with another event's. An event that is itself `private` at file scope is
  checked. One that is a `private` member of another type, or nested in such a member, doesn't
  compile; make that type `fileprivate`.

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
