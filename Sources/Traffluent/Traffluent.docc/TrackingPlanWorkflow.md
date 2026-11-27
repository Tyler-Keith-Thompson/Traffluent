# Exporting and Checking a Tracking Plan

Tell the people and services that read your events what each event holds, and hear about a change that would break their data before it ships.

## Overview

Analytics events have readers outside the app: whoever builds the dashboards, loads the warehouse,
runs the collector or writes the Android client. They need to know what `signed_up` holds, and
they need to know before a release changes it. A tracking plan tells them. It is the JSON Schema
(draft 2020-12) of every event the app tracks, exported from the Swift types and committed to the
repository beside them.

The example store app declares `signed_up` like this:

```swift
@Event(name: "signed_up", consent: .functional)
struct SignedUp {
    var plan: String
    var email: Sensitive<String>
    var referrer: String?
}
```

Its plan holds `signed_up.v1.schema.json`:

```json
{
  "$id": "signed_up.v1.schema.json",
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "additionalProperties": false,
  "properties": {
    "email": {
      "type": "string",
      "x-traffluent-sensitive": true
    },
    "plan": {
      "type": "string"
    },
    "referrer": {
      "type": [
        "string",
        "null"
      ]
    }
  },
  "required": [
    "plan"
  ],
  "title": "signed_up",
  "type": "object",
  "x-traffluent-consent-category": "functional",
  "x-traffluent-version": 1
}
```

A reader who doesn't know Swift can see that the event is at version 1 and is collected only with
`functional` consent. Every payload holds `plan` as a string, `referrer` may be `null`, and no
other property is allowed. `email` is personal data, marked `Sensitive` in the app, so a payload
may leave it out. The plan's index, `tracking-plan.json`, lists every event with its version and
consent category.

### What a committed plan gives you

**Event changes are reviewed with the code that makes them.** The check described below fails
whenever the events and the committed plan differ, until the plan is exported again. So a pull
request that changes an event also changes its JSON, and the people who depend on the event can
see the change before it ships. Rename `coupon` to `couponCode` in `checkout_started`, and the diff
shows `couponCode` added and `coupon` kept with `deprecated: true`. Whoever owns the chart of
coupon use can catch it in review. Without the plan, they would find out after the release, when
the chart drops to zero.

**Breaking changes are called out.** Some changes break data that already exists. Make
`checkout_started`'s `cartSize` a string at the same version, and the app versions already
installed keep sending an integer, which a collector validating against the new document rejects.
Records the app stored at that version no longer decode, and its store drops them. While the
committed plan still has the old shape, the check reports changes like these as breaking, names the
event and the property, and says to undo the change or raise the event's version. "Checking the
plan" below shows how to keep CI failing on them after the plan is exported again.

**Privacy review reads the same files.** Each event's consent category and each `Sensitive`
property are in its document. A change to either fails the check until the plan is exported again,
so it shows up in the pull request as well.

**Services can validate against it.** TraffluentCollector loads the exported directory and checks
each record's properties against its event's document. It rejects a record that doesn't match,
naming the property and the rule it broke, and its dashboards offer the plan's events and their
typed properties. Any JSON Schema 2020-12 validator can check payloads against the same documents.
A destination that redacts `Sensitive` values leaves them out of the record, and a document never
requires a `Sensitive` property, so the redacted record still validates.

### When you need one

You need a plan when someone else reads your events: a dashboard, a warehouse, a collector, or
another platform's client that tracks the same events. An app that sends to TraffluentCollector or
PostHog already builds the `TrackingPlan` their destinations read (`CollectorBatchEncoder(plan:)`,
`HTTPDestination.postHog(projectToken:host:plan:)`), so exporting it takes one small executable. A collector
running in production won't start without the exported plan.

You can skip it for a prototype whose events go only to the console or a log, where nothing
downstream can break. A plan describes events that have a schema, which `@Event` gives them.

### Making a plan

`TrackingPlan` (module ``/TrackingPlans``, a product of its own that `import Traffluent` leaves out)
turns schemas into the plan's files, one document per event and an index, as values.
`TrackingPlan()` takes the schema of every event the program declares with `@Event`, and of the
library's own, so an event is in the plan as soon as it is declared
(<doc:DefiningEvents#Finding-every-event>); `TrackingPlan(schemas:)` takes a list instead:

```swift
import TrackingPlans

let plan = try TrackingPlan()
let paths = plan.files.map(\.path)
// ["tracking-plan.json", ..., "checkout_started.v2.schema.json", "checkout_started.v2.example.json", ...]
```

The bytes depend on the schemas alone: keys sorted, two-space indentation, a trailing newline and
no timestamps. They are the same on every run and platform, so a diff of the plan shows only what
changed in the events.

### What each document says

Each document requires the properties that are neither optional, nor have a default value, nor
are `Sensitive`. It allows `null` for the optional ones and rejects any other property. It carries
the event's version and consent category (`x-traffluent-version`, `x-traffluent-consent-category`).
A `Sensitive` property is marked `x-traffluent-sensitive` and is never required, since a
destination that redacts it leaves it out; an array's `Sensitive` elements may be `null`, which is
what a redacted element becomes. A property with a default value is marked `x-traffluent-default`
and isn't required, since an earlier release's payload lacks it. A property of a raw-value enum is
its raw value's type, with its cases' raw values as `enum`. That holds for an enum declared inside
the event whose cases the macro can read, and for any other enum that is `CaseIterable`, such as
one declared elsewhere or one with a case under `#if`. A property of an enum that isn't
`CaseIterable`, or of a typealias of one, is a type the plan can't map, which accepts any value.

A property removed at the same version stays in the document with the schema it had, marked
`deprecated` and not required, so the payloads of releases that still send it validate: exporting
over the committed plan carries it forward. `TrackingPlan`'s documentation lists how each Swift
type maps.

Beside each document is the event's example, a conformance vector: the payload with every property
set to a fixed value its schema accepts (`"example"`, 0, `false`, one array element). Another
platform's client can encode the same event and compare it against the example.

### Exporting the plan

A tool can only read the schemas of types it is compiled against, so the plan is written by a small
executable in your package that links every module declaring your events:

```swift
// Package.swift
.executableTarget(name: "AppTrackingPlan", dependencies: [
    "AppEvents",
    .product(name: "TrackingPlans", package: "Traffluent"),
]),
```

The example package's executable, `StoreTrackingPlan`, is one. Its plan, `TrackingPlan.store`, is
`TrackingPlan()`: the store's own events and the ones the library tracks for it, such as screen
views and sessions, found in the modules it links:

```swift
import StoreAnalytics
import TrackingPlans

/// Writes the store app's tracking plan, `TrackingPlan.store`: `swift package
/// --allow-writing-to-package-directory export-tracking-plan`, from Examples/, writes it into
/// Examples/TrackingPlan, and `swift package check-tracking-plan` checks the events against it.
@main
struct StoreTrackingPlan: TrackingPlanCommand {
    static var trackingPlan: TrackingPlan {
        get throws(TrackingPlanError) { try .store }
    }
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
After an event's version is raised, it keeps the earlier version's document and example as they
are and lists them in the index, so a collector still accepts payloads from releases at that version.
[`Examples/TrackingPlan`](https://github.com/Tyler-Keith-Thompson/Traffluent/tree/main/Examples/TrackingPlan)
is the plan `StoreTrackingPlan` writes.

### Exporting an Iglu registry

Snowplow validates each event against a schema it looks up in an Iglu registry, by the URI the
event names (<doc:ChoosingDestinations#Snowplow>). The plan writes those schemas too, in the
layout of an Iglu static repository, which `igluctl` publishes to Iglu Server. Give the plugin the
Iglu vendor your Snowplow destination uses, and the kind of registry you publish to: `server` for
Iglu Server, `static` for a static repository:

```sh
swift package --allow-writing-to-package-directory export-tracking-plan --iglu-vendor com.example --iglu-registry server
```

It writes the plan into `TrackingPlan/`, as before, and the registry into `Iglu/`, or the directory
`--iglu-output` names. The executable does the same with
`iglu <vendor> server|static <registry-directory>`, and a program with
`TrackingPlan.writeIgluRegistry(to:vendor:registry:)`:

```swift
let plan = try TrackingPlan(schemas: [SignedUp.schema])
try plan.writeIgluRegistry(to: registry, vendor: "com.example", registry: .server)
// registry/schemas/com.example/signed_up/jsonschema/1-0-0
```

Each file is the event's document as a self-describing schema: `self` names the vendor, the event,
the format and the SchemaVer, `$schema` is Iglu's meta-schema, and there is no `$id`. For the
`signed_up` event above:

```json
{
  "$schema": "http://iglucentral.com/schemas/com.snowplowanalytics.self-desc/schema/jsonschema/1-0-0#",
  "additionalProperties": false,
  "properties": {
    "email": {
      "type": "string",
      "x-traffluent-sensitive": true
    },
    "plan": {
      "type": "string"
    },
    "referrer": {
      "type": [
        "string",
        "null"
      ]
    }
  },
  "required": [
    "plan"
  ],
  "self": {
    "format": "jsonschema",
    "name": "signed_up",
    "vendor": "com.example",
    "version": "1-0-0"
  },
  "title": "signed_up",
  "type": "object",
  "x-traffluent-consent-category": "functional",
  "x-traffluent-version": 1
}
```

Version N of an event is SchemaVer `N-0-0`, the URI every event of that version names. Iglu treats
a published schema as immutable, so writing again never changes or deletes a file. The export
compares each event with the newest schema of its version in the registry by what they mean, as
`check-tracking-plan` compares the plan, so a file reformatted since it was published still
matches:

- A version whose schema still matches is left as it is.
- A breaking change at the same version, such as a property made required or retyped, throws
  `IgluExportError.breakingChange(event:version:)`: raise the event's version instead.
- A compatible change, such as an optional property added or a property removed, is an ADDITION.
  For Iglu Server it is written as `N-0-1`, then `N-0-2`, each listing the earlier ones in
  `$supersedes`, and Snowplow validates events naming `N-0-0` against the newest of them, so
  releases already installed keep validating. A removed property stays in each new file,
  deprecated and not required, as it does in the plan's documents. Superseding needs Iglu Server
  0.11.0 or later and Enrich 3.8.0 or later. A static repository doesn't supersede, so for one the
  export throws `IgluExportError.additionNeedsNewVersion(event:version:)`: raise the event's
  version for every change.

Publish the new files before the release that sends them: Snowplow's collector accepts every
event, and one whose schema the registry lacks becomes a failed event, never loaded. The export
also throws for an event whose name holds anything but ASCII letters, digits, `-` and `_`, whose
version is below 1, or whose property has two patterns, which needs `allOf`, a keyword Snowplow's
validation doesn't support. The executable exits with status 65 for each of these.

### Checking the plan

One command fails when the Swift events no longer match the committed plan, with a line naming each
event and property that changed:

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
- a property that stops being `Sensitive` and has no default value and isn't optional, which makes
  it required;
- a deprecated property declared again with another type, or as required;
- an enum case renamed or removed, which changes the raw values a stored record may hold.

Anything else leaves the committed plan out of date, which fails with its own message telling you to
export it again: a new event, a new optional property or one with a default value, a removed
property, a deprecated one declared again as it was, a changed consent category, a property that
became `Sensitive`, an optional or defaulted one that stopped being `Sensitive`, or a new enum
case.

A constraint is compared keyword by keyword. Tightening one is breaking: a higher `minLength` or
`minimum`, a lower `maxLength` or `maximum`, a new bound, a new or changed `pattern`, an `enum`
that lost a raw value, or a new `enum`, as when a `String` property becomes an enum. Loosening one
only leaves the plan out of date. The `enum` is compared as a set, so reordering the cases
changes nothing but the files. An integer type narrowed to one of fewer bits tightens its bounds
the same way. Raising an event's version (`@Event(version: 3)`) is how a breaking change is made on
purpose: exporting then writes the new version's document beside the earlier one's.
`--plan <directory>` checks a plan committed elsewhere, and `--product <name>` picks the
executable, as it does for export.

The check compares the events with the plan in the same tree, and exporting writes whatever the
events say. So once a breaking change has been exported, the check passes, and the change reaches
review as a diff of the plan. To have CI fail it, check the events against the base branch's plan
too, with `--breaking-only`, here with the base plan's directory in `BASE_PLAN`:

```sh
swift package check-tracking-plan --plan "$BASE_PLAN" --breaking-only
```

It fails on a breaking difference, and when the directory holds no plan or the check can't run. A
base plan that is only out of date, as it is whenever the change adds an event, passes, with its
differences printed for information.

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
    @Test("The store app's events match its committed tracking plan")
    func eventsMatchTheTrackingPlan() throws {
        let plan = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("TrackingPlan")
        expectTrackingPlan(try StoreTrackingPlan.trackingPlan, matches: plan)
    }
}
```

It records an issue with the report the command prints. `TrackingPlan.check(against:)` returns the
same comparison as a value, each `TrackingPlanDifference` with whether it `isBreaking`.
