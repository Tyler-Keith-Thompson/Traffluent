# ``Trackers``

The tracker app code tracks events with, and what it applies to each event before it is delivered: enrichers, samplers and consent.

## Overview

A ``Tracker`` is a value. ``Tracker/track(_:file:fileID:function:line:column:)`` only queues the
event, from any thread. A worker the tracker owns, never on the main actor, does the rest in the
order events were tracked: it makes the event's `EventRecord`, checks its constraints, runs the
enrichers (``/Events/Enricher``) on the context it was tracked in, applies the ``Sampler``s and
the ``Consent``, writes the record to the tracker's store if it has one, and publishes it to
``Tracker/records``.
``Tracker/flush()`` waits for the worker to catch up; ``Tracker/finish()`` does too, then ends the
records.

Build one tracker where the app starts. Pass it down, or bind it to a task with
``withTracker(_:_:)-7fax9`` and read it anywhere inside with ``Tracker/current``. Where no
binding reaches, as in a detached task, ``Tracker/current`` is the tracker
``Tracker/bootstrap(_:)`` made the process's default, once, at launch. With neither, it drops
every event like ``Tracker/noOp`` and logs a warning for the first one at each call site.
``Tracker/enriched(by:)`` gives a copy that adds to the context of the events tracked through it
alone, for code a task-local context doesn't reach. To enrich only what one destination receives, apply
`enriched(by:)` to that destination instead (module `Destinations`).

A sampler's rate is a ``/Events/SampleRate``, and each record it keeps carries that rate as its
``/Events/SampleRateKey``; both are in the `Events` module, as a store keeps the rate beside its
record.

The tracker reports every event it drops: one that breaks a declared constraint on
``Tracker/rejectionReports``, one a sampler leaves out on ``Tracker/samplingDropReports``, and a
record a consent drops on ``Consent/dropReports``.

Delivering a tracker's records to destinations is `batch()` and `deliver(to:)` in the
`Destinations` module, and keeping them on disk is a `RecordStore` from `Persistence`. For a
test that checks what its code tracked, `withRecordingTracker` in `TrackerTesting` does the setup.

```swift
enum ExperimentKey: ServiceContextKey {
    typealias Value = String
}

let consent = Consent([.analytics: .granted])
let tracker = Tracker(
    consent: consent,
    enrichers: [Enricher { $0[ExperimentKey.self] = "new-checkout" }]
)
withTracker(tracker) {
    Tracker.current.track(SignedUp(plan: "pro"))
}
await tracker.finish()
for await record in tracker.records {
    print(record.name, record.context[ExperimentKey.self] ?? "none")  // SignedUp new-checkout
}
```

The umbrella guide on this area is
[Tracking Events](https://tyler-keith-thompson.github.io/Traffluent/documentation/traffluent/trackingevents).

## Topics

### Tracking

- ``Tracker``
- ``withTracker(_:_:)-7fax9``
- ``withTracker(_:_:)-24yuc``
- ``TrackerAlreadyBootstrapped``

### Sampling

- ``Sampler``

### Consent

- ``Consent``
- ``ConsentStatus``
- ``ConsentDropReport``
- ``NegativeHeldRecordLimit``

### Reports

- ``RejectionReport``
- ``SamplingDropReport``
