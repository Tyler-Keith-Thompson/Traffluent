# ``TrackingPlans``

Export the JSON Schema of every event an app tracks as a tracking plan, and check the events against the plan committed before them.

## Overview

A ``TrackingPlan`` turns events' schemas into files: an index, `tracking-plan.json`, and for each
event a JSON Schema (draft 2020-12) document and an example payload. The files are values, so the
same schemas give the same bytes on every run and platform, ready to commit for the people and
tools outside the app.

Checking compares the plan the events make now with the committed one by what the files mean. The
``TrackingPlanCheck`` is a match, a plan that is only out of date, or one with a breaking
difference: a change that, at the same version, would leave a stored record or an
already-released app's payload unable to decode or validate. Each ``TrackingPlanDifference`` names
the event, the property and the change, and says whether it is breaking.

Only code compiled against the app's event types can read their schemas, so the app writes a small
executable of its own: a type that conforms to ``TrackingPlanCommand``, marked `@main`. It writes
the plan to a directory, or checks it with `check`. To run the check from the app's tests instead,
use `TrackingPlanTesting`. The schemas usually come from `@Event` (module `EventMacros`).

The module is a product of its own that `import Traffluent` leaves out.

```swift
import TrackingPlans
import Traffluent

@Event(name: "signed_up")
struct SignedUp {
    var plan: String
}

let plan = TrackingPlan(schemas: [SignedUp.schema])
let check = plan.check(against: plan.files)  // .matches
let paths = plan.files.map(\.path)
// ["tracking-plan.json", "signed_up.v1.schema.json", "signed_up.v1.example.json"]
```

The guide [Exporting and Checking a Tracking Plan](https://tyler-keith-thompson.github.io/Traffluent/documentation/traffluent/trackingplanworkflow)
covers the executable, the command plugins and the test.

## Topics

### Making a plan

- ``TrackingPlan``
- ``TrackingPlan/File``
- ``TrackingPlanError``

### Writing a plan

- ``TrackingPlan/files``
- ``TrackingPlan/files(carryingForward:)``
- ``TrackingPlan/write(to:)``
- ``TrackingPlanCommand``

### Checking a plan

- ``TrackingPlan/check(against:)``
- ``TrackingPlan/check(againstDirectory:)``
- ``TrackingPlanCheck``
- ``TrackingPlanDifference``
