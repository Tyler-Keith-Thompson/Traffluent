# Identifying People

Traffluent knows people only by a pseudonymous session. An identifier that outlives one is yours to add, store, reset and gate with consent.

## Overview

The identifier Traffluent makes is the session's: `Enricher.sessions(timeout:kinds:)` (module
``/Sessions``) stamps every record's context with its `SessionKey`, a version 7 UUID (the session's
start time, then random bits) derived from nothing else and held in the enricher's memory only. It is never written to disk, and the next launch
starts a new session with a new identifier.

Nothing else identifies the person unless the app asks. Traffluent keeps no persisted anonymous or
device identifier, and has no call that identifies a user or aliases one identifier to another.
The one identifier it offers that outlives a session is the operating system's own:
`Enricher.vendorIdentifier()` (module ``/StandardContext``) adds the platform's
`identifierForVendor` as `VendorIdentifierKey`, a `Sensitive` value. The system owns it, gives it
to every app of one vendor on the device and resets it once they are all removed; Traffluent reads
it, never stores it and never makes one up where the system has none, as on macOS and Linux. Like
your own identifier below, adding it is the app's decision, its consent included.

Every record also has an `EventRecord.id`, a random UUID drawn when its event is tracked. It
identifies the record, not the person: each record draws its own, so no two records share one and
it links nothing together, and a store keeps it only with its record until that record is
delivered. It is there so a collector that receives a record twice, after a redelivery, keeps one
copy.

An app that wants another link, such as its own account identifier, adds it with an enricher of
its own, and owns what that takes: where the identifier is stored, when it is cleared, and the
user's consent to it.

### Add your identifier

Declare a `ServiceContextKey` for the identifier, a consent category for it, and keep the
identifier where your app keeps its account (the Keychain, say). Give the key a `Sensitive`
value, so a destination reads it only through the record it arrived in:

```swift
extension ConsentCategory {
    static let identification = ConsentCategory("identification")
}

enum AccountKey: ServiceContextKey {
    typealias Value = Sensitive<String>
}

final class SignedInAccount: Sendable {
    private let identifier = Mutex<String?>(nil)

    var current: String? {
        identifier.withLock { $0 }
    }

    func signIn(as id: String) {
        identifier.withLock { $0 = id }  // and save it to the Keychain
    }

    func signOut() {
        identifier.withLock { $0 = nil }  // and delete it from the Keychain
    }
}
```

Then an enricher sets the key on every record's context, beside the session's:

```swift
let consent = Consent([.analytics: .granted, .identification: .granted])
let account = SignedInAccount()
let accountIdentifier = Enricher { context in
    guard consent.status(of: .identification) == .granted, let id = account.current else { return }
    context[AccountKey.self] = Sensitive(id)
}
let tracker = Tracker(consent: consent, enrichers: [.sessions(), accountIdentifier])
```

### Ask for consent

A `Consent` gates events by their type's `Event.consentCategory`, not by values in their
context, so it can't hold or drop an identifier on its own. Give the identifier a category of its
own, as above, and have the enricher ask the consent for it: it adds nothing unless the user has
granted it. The enricher reads the status when the tracker's worker reaches each event, shortly
after it is tracked, so a denial leaves the identifier off every event the worker reaches after
it. Records already enriched keep it, those the consent holds for their own category included.

### Reset it on sign-out

Clear the identifier where your app signs the user out. The enricher runs on the tracker's worker
after `track` returns, so an event tracked just before sign-out can reach it after and go without
the identifier. Flush first to keep it on the events tracked while signed in:

```swift
account.signIn(as: "account-42")
tracker.track(CheckoutStarted(itemCount: 3))  // carries AccountKey and SessionKey

await tracker.flush()
account.signOut()
tracker.track(CheckoutStarted(itemCount: 1))  // carries SessionKey only
```

A store keeps no record's context, so a record recovered from an earlier run arrives without
either identifier.

### Keep it from destinations

A destination reads the identifier through the record, which answers `nil` once a delivery
redacts it. Give `redactingSensitiveValues()` to each destination that mustn't receive it:

```swift
let delivery = tracker.records.batch().deliver(
    to: ownBackend,
    vendor.redactingSensitiveValues()
)
```

```swift
let accountID = record.context[AccountKey.self].flatMap(record.reveal)  // nil for the vendor
```

Printing, interpolating or dumping a `Sensitive` value shows `<redacted>`, so a destination that
writes records out as text never writes the identifier.
