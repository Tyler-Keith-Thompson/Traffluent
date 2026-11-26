# Changing an Event

An event's version counts the changes that records stored before them can't be read through, and only those. A compatible change keeps the version; a breaking one raises it.

## Overview

An app updates with records still on disk: a store (``/Persistence``, ``/GRDBPersistence``) keeps
each record until it is delivered, so the release that reads it back may declare the event
differently from the one that wrote it. Each record is stored with its event's properties under
their names and with the event's `Event.schemaVersion`, the `version` of `@Event(version:)`
(``/EventMacros``), 1 unless the event says otherwise.

- A record stored at the version its type has now is read by each property's name, in any order.
- A record stored at another version is dropped without being read, and reported on the store's
  `dropReports` as `DropReport.versionMismatch(event:storedVersion:currentVersion:recordCount:)`,
  naming the event and both versions. That holds after a rollback too, when the stored version is
  the later one.
- A record without a version has none to compare, so it is read by each property's name whatever
  version its type has now, and dropped as `DropReport.undecodable(recordCount:)` when that fails.

Records are never migrated from one version to another, and a record is never delivered with a
made-up value.

The tracking plan (``/TrackingPlans``) exports each event's version, and its check compares the
events with the committed plan: a breaking change at the version the plan has fails it, with a line
naming the event, the property and the change. With the version raised, the check reports only the
raise, and exporting the plan again writes the new version's document beside the index.

## Compatible changes

Each of these keeps the version. The examples change this event, as released:

```swift
@Event(name: "checkout_started")
struct CheckoutStarted {
    var cartSize: Int
    var screen: String
}
```

**Adding an optional property.** A record stored before reads it as `nil`.

```swift
@Event(name: "checkout_started")
struct CheckoutStarted {
    var cartSize: Int
    var screen: String
    var coupon: String?
}
```

**Adding a property with a default value.** A record stored before reads it as the value the
declaration gives it. The plan marks the property `x-traffluent-default` and leaves it out of
`required`, as an earlier release's payload lacks it.

```swift
@Event(name: "checkout_started")
struct CheckoutStarted {
    var cartSize: Int
    var screen: String
    var currency: String = "USD"
}
```

**Removing a property.** A record stored before holds it still, and reading skips it. The plan keeps
it in the version's document, with the schema it had, marked `deprecated` and not required, so an
earlier release's payload that holds it still validates. Declaring it again is compatible with the
schema it had, as an optional property or one with a default value; another type, or a required
one, is breaking.

```swift
@Event(name: "checkout_started")
struct CheckoutStarted {
    var cartSize: Int
}
```

The plan's check reports each as a difference that leaves the committed plan out of date: export
it again.

## Breaking changes

Each of these needs the version raised. A record stored before the change can't be read as the new
shape, so the store drops it, reporting both versions.

**Changing a property's type.**

```swift
@Event(name: "checkout_started", version: 2)
struct CheckoutStarted {
    var cartSize: Double  // an Int at version 1
    var screen: String
}
```

**Adding a required property with no default value.**

```swift
@Event(name: "checkout_started", version: 2)
struct CheckoutStarted {
    var cartSize: Int
    var screen: String
    var paymentMethod: String
}
```

**Making an optional property required.**

```swift
@Event(name: "checkout_started", version: 2)
struct CheckoutStarted {
    var cartSize: Int
    var screen: String  // a String? at version 1
}
```

Left at version 1, each fails the plan's check: `checkout_started v1: property "cartSize" changed
type from {"type": "integer"} to {"type": "number"}`, `checkout_started v1: required property
"paymentMethod" was added without a default value`, `checkout_started v1: property "screen" was
optional and is now required`. A store that reads a record of such a change anyway drops it as
`DropReport.undecodable(recordCount:)`, with no versions to name.

The check treats a few more changes as breaking: a renamed or removed event; a default value
removed from a required property, as a record stored before the property was added can't be read;
a tightened constraint (`@Constrained`), which rejects values an earlier release tracked; and an
enum case renamed or removed, whose stored raw value no longer decodes. Adding an enum case is
compatible. Turning a `String` property into an enum is a breaking change that needs a version
bump.

A change of meaning alone, such as a property that keeps its name and type but is measured in other
units, raises the version too. Its records would still read, and raising the version keeps them
from being read as the new meaning.

## Hand-written events

`@Event` keeps the version, the coding and the schema in step. An event that writes its own
conformances instead (the `Event` protocol's documentation shows one) must do that itself: declare
`schemaVersion`, read a property with a default value only when its key is present
(`try container.decodeIfPresent(String.self, forKey: .currency) ?? "USD"`), and give its
`EventSchema` the same version and `hasDefaultValue: true` for that property, so the plan and its
check see what the store does.
