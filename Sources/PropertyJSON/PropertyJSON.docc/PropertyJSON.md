# ``PropertyJSON``

The vendor-neutral pieces a JSON `BatchEncoder` is built from: properties, context, timestamps, identity and batch splitting.

## Overview

A vendor destination's encoder writes each record as the vendor's JSON. This module has the parts
every such encoder needs, so each vendor module writes only its own format:

- ``PropertyReader`` reads an event's properties through its schema in a `TrackingPlan`, and
  writes a `Sensitive` value only when asked to and the record reveals it.
- `EventRecord.standardContext` is the standard context (app, device, locale, network, operating
  system) as JSON, and `flattened(separator:)` turns nested JSON into one level of dotted keys.
- `Date.iso8601Timestamp` and `Date.millisecondsSince1970()` are the two timestamp formats vendors
  take, both rounded down to the millisecond.
- `EventRecord.pseudonymousIdentity` is the record's session, or the record itself when it has
  none, and `EventRecord.deduplicationID` the identifier a vendor drops repeats by.
- ``BatchLimit`` splits a batch into requests of a ``JSONEnvelope`` within a vendor's limits on
  records and bytes, and leaves out a record that fits in none of them as a `SkippedRecord`
  (module ``/HTTPDestinations``).

`import Traffluent` leaves this module out; a vendor module imports it on its own.

```swift
import PropertyJSON
import TrackingPlans

let reader = PropertyReader(plan: plan)
let event: JSON = .object([
    "name": .string(record.name),
    "id": .string(record.deduplicationID),
    "user": .string(record.pseudonymousIdentity.uuid.uuidString.lowercased()),
    "at": .integer(try record.timestamp.millisecondsSince1970()),
    "properties": .object(try reader.properties(of: record, includingSensitiveValues: false)),
    "context": .object(try record.standardContext.flattened()),
])
```

The guide [Writing a Vendor Destination](https://tyler-keith-thompson.github.io/Traffluent/documentation/traffluent/writingavendordestination)
builds a whole encoder from these.

## Topics

### Reading properties

- ``PropertyReader``
- ``PropertyReadingError``

### Context and identity

- ``PseudonymousIdentity``
- ``FlattenedKeyCollision``

### Timestamps

- ``UnrepresentableTimestamp``

### Splitting a batch into requests

- ``BatchLimit``
- ``InvalidBatchLimit``
- ``JSONEnvelope``
