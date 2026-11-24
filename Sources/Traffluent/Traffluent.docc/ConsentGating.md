# Consent Gating

Deliver an event only once the user grants the purpose it is collected for.

## Overview

Each event type names the purpose it is collected for, its `consentCategory`, which is `.analytics`
unless the type says otherwise. Give the tracker a `Consent`, which the app updates as the user
decides, and an event reaches a destination only once its category is granted:

```swift
struct AdClicked: Event {
    static let consentCategory = ConsentCategory.advertising
    var campaign: String
}

let consent = Consent([.analytics: .granted])
let tracker = Tracker(consent: consent)
let delivery = tracker.records.batch().deliver(
    to: ConsoleDestination(),
    ConsoleDestination().accepting(.advertising)
)
tracker.track(SignedUp(plan: "pro"))          // delivered: analytics is granted
tracker.track(AdClicked(campaign: "spring"))  // held: advertising is undecided
consent.grant(.advertising)                   // delivers the held AdClicked
```

A tracker given no consent delivers every event.

### Undecided, granted and denied

A category is undecided until the app grants or denies it. While it is undecided, its events are
held in memory, not written to a store, up to `heldRecordLimit` records (1,000 by default) across
every category, the oldest dropped first when the hold is full. Granting delivers them in the order
they were tracked, before anything tracked after the grant. Denying drops them. Events tracked while
their category is denied are never collected.

`grant` and `deny` return at once: they record the decision, and the tracker's worker releases or
drops what it held. Every drop of a record that was held or kept is reported on
`consent.dropReports` as a `ConsentDropReport` as it happens, so none is lost silently. Held
records are lost if the app ends first.

Records that a store recovered from an earlier run are gated again as the tracker starts. They are
held outside the bound, since the store still keeps them, and the store forgets each one that is
denied.

### Destinations

A destination receives every category the consent lets through, unless `accepting(_:)` narrows it
to the categories it serves, as the second destination above takes only advertising.
