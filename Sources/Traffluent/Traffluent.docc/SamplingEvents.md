# Sampling Events

Keep a seeded fraction of the events a tracker tracks, event by event or a whole session at once.

## Overview

Sampling lives in module ``/Trackers``, and sampling by session uses ``/Sessions``. Nothing is
sampled until the app gives the tracker its samplers:

```swift
import Traffluent

@Event
struct Scrolled {
    var offset: Int
}

let tracker = Tracker(
    enrichers: [.sessions()],
    samplers: [.events(of: Scrolled.self, rate: 0.1), .sessions(rate: 0.5)]
)
tracker.track(Scrolled(offset: 120))  // if kept, its record's context[SampleRateKey.self]?.value is 0.05
```

### Samplers

- `.events(of:rate:)` keeps each event of a type with the probability its `SampleRate` gives.
- `.events(where:rate:)` does the same for each record a predicate selects. Both decide each event
  on its own.
- `.sessions(rate:)` keeps or drops every record of a session alike, its `SessionStarted` and
  `SessionEnded` with it.
- `.grouped(by:rate:)` does the same for the groups that any context key's values make.

A rate is in 0 ... 1. A literal outside that range, or `SampleRate(_:)` given one, traps;
`SampleRate(checked:)` throws `InvalidSampleRate` instead. A record is kept only if every sampler
that applies to it keeps it. A kept record carries the product of their rates as its
`SampleRateKey`, so a destination can count it as `1 / value` records. A record that no sampler
applies to is always kept and carries no key.

### When sampling runs

The tracker's worker samples each record after its enrichers, whose keys a sampler can read, and
before its consent and its store. So a dropped event is never held, written to disk or delivered.
Each drop is reported on `samplingDropReports`, merged into one report per event type while unread,
as rejections are.

The decisions come from the tracker's `samplingSeed`, drawn from the system's random number
generator once per tracker unless you pass one. They are the same on every platform and Swift
release, so with the seed fixed, which events are kept is fixed too:

```swift
let tracker = Tracker(samplers: [.events(of: Scrolled.self, rate: 0.1)], samplingSeed: 42)
for offset in 0 ..< 100 {
    tracker.track(Scrolled(offset: offset))
}
await tracker.finish()
for await report in tracker.samplingDropReports {
    print(report)  // Scrolled: 89 sampled out
}
```

A session's decision is made from the seed and the session's identifier alone, so nothing records
it. The sampler keeps only the current session's decision, in memory, and never writes the
identifier anywhere. Records that a store recovered from an earlier run were sampled in that run,
and come back in the top-level context, without their rate.
