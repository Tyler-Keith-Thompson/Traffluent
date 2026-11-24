# Exporting and Checking a Tracking Plan

Export the JSON Schema of every event an app tracks, commit it, and fail the build when the events stop matching it.

## Overview

The events' Swift types are the source of their schema. A tracking plan, the JSON Schema (draft
2020-12) of every event an app tracks, is exported from them for the people and tools outside the
app. `TrackingPlan` (module ``/TrackingPlans``, a product of its own that `import Traffluent`
leaves out) turns schemas into the plan's files, one document per event and an index, as values:

```swift
import TrackingPlans

let plan = TrackingPlan(schemas: [CheckoutStarted.schema])
let paths = plan.files.map(\.path)
// ["tracking-plan.json", "checkout_started.v2.schema.json", "checkout_started.v2.example.json"]
```

The bytes depend on the schemas alone: keys sorted, two-space indentation, a trailing newline and
no timestamps, the same on every run and platform, so the plan can be committed and reviewed.

### What each document says

Each document requires the properties that are neither optional nor have a default value, allows
`null` for the optional ones, and rejects any other property. It carries the event's version and
consent category (`x-traffluent-version`, `x-traffluent-consent-category`). A `Sensitive`
property is marked `x-traffluent-sensitive`, and one with a default value is marked
`x-traffluent-default` and isn't required, since an earlier release's payload lacks it.

A property removed at the same version stays in the document with the schema it had, marked
`deprecated` and not required, so the payloads of releases that still send it validate: exporting
over the committed plan carries it forward. `TrackingPlan`'s documentation lists how each Swift
type maps.

Beside each document is the event's example, a conformance vector: the payload with every property
set to a fixed value its schema accepts (`"example"`, 0, `false`, one array element). Another
platform's client can encode the same event and compare it against the example.

### Exporting the plan

A tool can only read the schemas of types it is compiled against, so the plan is written by a small
executable in your package that lists your events:

```swift
// Package.swift
.executableTarget(name: "AppTrackingPlan", dependencies: [
    "AppEvents",
    .product(name: "TrackingPlans", package: "Traffluent"),
]),
```

The example package's executable, `StoreTrackingPlan`, is one:

```swift
import StoreEvents
import TrackingPlans

/// Writes the store's tracking plan: `swift package --allow-writing-to-package-directory
/// export-tracking-plan`, from Examples/, writes it into Examples/TrackingPlan.
@main
struct StoreTrackingPlan: TrackingPlanCommand {
    static let trackingPlan = TrackingPlan(schemas: [
        CheckoutStarted.schema,
        OrderCompleted.schema,
        SignedUp.schema,
    ])
}
```

Then one command, run from the package's directory, builds it and writes the plan into
`TrackingPlan/`:

```sh
swift package --allow-writing-to-package-directory export-tracking-plan
```

The `export-tracking-plan` plugin runs the package's one executable target that depends on
``/TrackingPlans``. `--product <name>` picks one of several, and `--output <directory>` writes
elsewhere in the package. Writing again deletes the documents of events the plan no longer lists.
[`Examples/TrackingPlan`](https://github.com/Tyler-Keith-Thompson/Traffluent/tree/main/Examples/TrackingPlan)
is the plan `StoreTrackingPlan` writes.

### Checking the plan

The committed plan is the contract every platform that sends the events agrees on. One command
fails when the Swift events no longer match it, with a line naming each event and property that
changed:

```sh
swift package check-tracking-plan
```

A difference is breaking when, at the same version, a record a store still holds or a payload an
already released app sends may stop decoding or validating:

- a removed or renamed event;
- a retyped property;
- an optional property made required;
- a new required property without a default value;
- a default value removed;
- a deprecated property declared again with another type, or as required.

Anything else leaves the committed plan out of date, which fails with its own message telling you to
export it again: a new event, a new optional property or one with a default value, a removed
property, a deprecated one declared again as it was, or a changed consent category.

A constraint is compared keyword by keyword. Tightening one is breaking: a higher `minLength` or
`minimum`, a lower `maxLength` or `maximum`, a new bound, a new or changed `pattern`. Loosening one
only leaves the plan out of date. An integer type narrowed to one of fewer bits tightens its bounds
the same way. Raising an event's version (`@Event(version: 3)`) is how a breaking change is made on
purpose: the new version gets a document of its own. `--plan <directory>` checks a plan committed
elsewhere, and `--product <name>` picks the executable, as it does for export.

### Checking from a test

The same check runs from a test, so it runs wherever the app's tests do. Add the
``/TrackingPlanTesting`` product to a test target that depends on the executable, as the example
package's `StoreTrackingPlanTests` does:

```swift
import Foundation
@testable import StoreTrackingPlan
import Testing
import TrackingPlanTesting

@Suite("StoreTrackingPlan")
struct StoreTrackingPlanTests {
    @Test("The store's events match its committed tracking plan")
    func eventsMatchTheTrackingPlan() {
        let plan = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("TrackingPlan")
        expectTrackingPlan(StoreTrackingPlan.trackingPlan, matches: plan)
    }
}
```

It records an issue with the report the command prints. `TrackingPlan.check(against:)` returns the
same comparison as a value, each `TrackingPlanDifference` with whether it `isBreaking`.
