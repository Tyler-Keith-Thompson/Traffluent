# Persisting Records

Keep each record on disk until it is delivered, so a record the app tracked survives the process ending.

## Overview

Without a store, records live in memory only: whatever isn't delivered when the process exits is
lost. Give the tracker a `SegmentStore` (module ``/Persistence``) and the tracker's worker writes
each record to disk before publishing it. If this launch ends first, the record is delivered on the
next one:

```swift
@Event(name: "signed_up")
struct SignedUp {
    var plan: String
}

let store = try SegmentStore()
let tracker = Tracker(store: store)
let delivery = tracker.records.batch().deliver(to: ConsoleDestination())
```

A record is durable once it is written, not once `track` returns. A record tracked moments before
the process is killed, which the worker hadn't reached yet, is lost. As the app moves to the
background, call `await tracker.flush()`, then `store.synchronize()`, or let `trackLifecycle` do
both (<doc:AutomaticTracking>).

`@Event` makes the event `Codable`, the conformance a store writes it through
(<doc:DefiningEvents>). Swift's synthesized `Codable` conformance, or one written by hand, works
too. `@Event` writes a `Date` property, and each date in a `[Date]` or `[Date?]`, as the seconds
since 2001 it stores, so it reads back exactly. A `Date` the macro doesn't reach, inside a
`Codable` type of your own or in a synthesized conformance, takes the CBOR package's own form,
seconds since 1970, and reads back to within a rounding of a microsecond's scale.

### What the store writes

`SegmentStore()` keeps every event the app declares with `@Event`, in any of its modules, and the
library's own, with no list to keep (<doc:DefiningEvents#Finding-every-event>). To keep only some,
list them: `SegmentStore(events: [SignedUp.self])`. Any other event is kept in memory only:
delivered in this run, never written, and reported once on `dropReports` as `notPersisted`.

The store writes each event through its `Codable` conformance in CBOR (RFC 8949), a compact binary
encoding, as a map of its properties under their names, which any CBOR decoder can read. A
`Sensitive` value is written in full, as the store keeps it for destinations that reveal it, and
read back only by the store.

The log is a directory of append-only segment files: in Application Support on Apple platforms
(excluded from backups), and in the XDG state directory on Linux, unless `directory:` says
otherwise. Each segment starts with a magic number and format version. Each record, a CBOR map of
its identifier, timestamp, event name and schema version, call site and event, is framed by its
length and CRC-32. A segment is deleted once every record in it has been delivered, so a log with
nothing left to send holds no files.

### Bounds, drops and recovery

The log never holds more than its byte bound, 5 MiB unless `byteBound:` says otherwise. When a
record won't fit, the oldest segments are dropped, and each drop is reported on the store's
`dropReports` with the number of records dropped and their timestamp range. So is a record whose
write to disk fails, which is kept in memory only. Recovery cuts a segment at its first torn or
corrupt record, keeps every record before it, and reports what it cut.

A record whose delivery had started when the app ended comes back with `isRedelivered` set, so a
destination can tell it may have been sent before. A record is never sent without that mark on disk
first; one whose mark can't be written waits for a later launch. After a rollback, a segment
written by a newer release, in a later format version, is left untouched. One in an earlier format
version is deleted and reported as a corruption. Every segment Traffluent 0.0.44 or earlier wrote
is in an earlier format, so updating from one of those releases drops the records it left
undelivered, each segment reported on `dropReports` as `.corruption`.

The store makes the log durable against power loss too (`fsync`), once per batch. Call
`store.synchronize()`, after `tracker.flush()`, as the app moves to the background or terminates.

A recovered record keeps these keys of its `ServiceContext`, written in the record's own bytes and
deleted when the store deletes them (a `SegmentStore`: once the record's whole segment is
delivered):

- its session's `SessionKey`, so a vendor destination sends it under the identity it was first sent
  with, and, where the vendor deduplicates, the vendor can drop a second copy;
- its `SampleRateKey`, so a destination weights it by the rate it was sampled at;
- its `ScreenKey` and its standard context (`ApplicationKey`, `DeviceKey`, `OperatingSystemKey`,
  `LocaleKey`, `NetworkKey`), so it is counted under the screen, app version, device, system, locale
  and network it was tracked on, not this run's. A locale is kept as its identifier.

The store writes these keys whatever set them, so don't build a screen name, or an app or device
value, from user data: an email address in a screen name would sit on disk until the record is
delivered.

A key the record didn't have comes back absent. Nothing else is kept, so the record otherwise comes
back in the top-level context. A store never writes `VendorIdentifierKey`. It doesn't write a key
of your own either, an account ID say, since it can't tell one from an identifier. Nor does it keep
the trace, since the span ended with the earlier run. A destination
that needs one of those must cope with a recovered record that lacks it.

### Changing an event's type

An event's type can change while records of it are still on disk, because each property is found
by its name: an app update reads the records the release before it left. A property removed since
is skipped, an optional property added since reads as `nil`, one with a default value added since
reads as its default, and properties can be reordered. Those changes keep the event's
`schemaVersion`, which is 1 unless the event says otherwise.

A change the earlier records can't be read through raises the version: a property's type changed,
a required property added without a default, an optional property made required. A record stored
at a different version from its type's current one is dropped without being read, and reported on
`dropReports` with the event and both versions. A record without a version has none to compare and
is read by name. A record that can't be read at the same version, after such a change made without
a new version, is dropped and reported as undecodable. Neither is ever delivered with a made-up
value, and records are never migrated from one version to another. <doc:ChangingEvents> lists each
kind of change.

### A GRDB database

An app on Apple platforms that already keeps a GRDB database can keep its records there instead.
`DatabaseStore(database:table:byteBound:)` (module ``/GRDBPersistence``, a product of its own that
`import Traffluent` leaves out) takes the app's `DatabaseQueue` or `DatabasePool` and a table name,
keeps the same events as `SegmentStore()`, or those `DatabaseStore(events:database:)` lists,
creates the table with a migration of its own, and opens no second SQLite database.

It makes the same promises as `SegmentStore`, and it doesn't read the rows Traffluent 0.0.44 or
earlier wrote either: each is deleted at recovery and reported as `.undecodable`, or as
`.versionMismatch` where its stored version differs from its type's. The worker commits each record
before publishing it.
A batch is marked before it goes out, and its rows are deleted once it is delivered, with the pages
they free zeroed. In WAL mode the log keeps a deleted row's bytes until `store.synchronize()`
truncates it, which it can't do while another connection is using the database (the module's
article says what stays behind then). The table is
bounded by its records' encoded bytes, with the oldest dropped and reported, and records are
encoded the same way.
