// The README's examples, verbatim, so the README cannot drift from the code.

import EventMacros
import Foundation
import Instrumentation
import SystemPackage
import Traffluent
import Testing

@Suite("README examples", .timeLimit(.minutes(1)))
struct READMEExamplesTests {
    struct SignedUp: Event {
        var plan: String
    }

    @Test("Usage")
    func usage() async throws {
        let tracker = Tracker()
        let delivery = tracker.records.batch().deliver(to: ConsoleDestination())
        tracker.track(SignedUp(plan: "pro"))
        await tracker.finish()
        try await delivery.execute()  // prints: SignedUp SignedUp(plan: "pro")
    }

    @Test("Batching")
    func batching() async throws {
        let tracker = Tracker()
        let delivery = tracker.records
            .batch(strategy: .either(.count(50), .time(interval: .seconds(10), clock: ContinuousClock())))
            .deliver(to: ConsoleDestination(), batchBufferLimit: 10)
        await tracker.finish()
        try await delivery.execute()
    }

    @Test("Tracking from anywhere")
    func trackingFromAnywhere() async throws {
        let tracker = Tracker()
        withTracker(tracker) {
            Tracker.current.track(SignedUp(plan: "pro"))
        }
        await tracker.finish()
        try await tracker.records.batch().deliver(to: ConsoleDestination()).execute()  // prints: SignedUp SignedUp(plan: "pro")
    }

    enum ScreenKey: ServiceContextKey {
        typealias Value = String
    }

    @Test("Context and enrichers")
    func contextAndEnrichers() async throws {
        let screen = Enricher { context in
            context[ScreenKey.self] = "Checkout"
        }
        let tracker = Tracker(enrichers: [screen])
        tracker.track(SignedUp(plan: "pro"))  // its record's context[ScreenKey.self] is "Checkout"
        await tracker.finish()
        try await tracker.records.batch().deliver(to: ConsoleDestination()).execute()
    }

    struct AdClicked: Event {
        static let consentCategory = ConsentCategory.advertising
        var campaign: String
    }

    @Test("Consent")
    func consent() async throws {
        let consent = Consent([.analytics: .granted])
        let tracker = Tracker(consent: consent)
        let delivery = tracker.records.batch().deliver(
            to: ConsoleDestination(),
            ConsoleDestination().accepting(.advertising)
        )
        tracker.track(SignedUp(plan: "pro"))          // delivered: analytics is granted
        tracker.track(AdClicked(campaign: "spring"))  // held: advertising is undecided
        consent.grant(.advertising)                   // delivers the held AdClicked
        await tracker.finish()
        try await delivery.execute()

        #expect(consent.heldRecordCount == 0)
    }

    struct SignedIn: Event {
        var email: Sensitive<String>
    }

    @Test("Sensitive values and call sites")
    func sensitiveValuesAndCallSites() async throws {
        let backend = InMemoryDestination()
        let vendor = InMemoryDestination()
        let tracker = Tracker()
        let delivery = tracker.records.batch().deliver(
            to: backend,
            vendor.redactingSensitiveValues().droppingCallSite()
        )
        tracker.track(SignedIn(email: Sensitive("ada@example.com")))
        await tracker.finish()
        try await delivery.execute()
        let event = backend.events(of: SignedIn.self)[0]
        let email = backend.records[0].reveal(event.email)    // "ada@example.com"
        let redacted = vendor.records[0].reveal(event.email)  // nil
        let callSite = vendor.records[0].sourceLocation       // nil

        #expect(email == "ada@example.com")
        #expect(redacted == nil)
        #expect(callSite == nil)
    }

    @Test("Persistence")
    func persistence() async throws {
        // The README's store uses the default directory; this one uses a scratch directory so the
        // test leaves nothing behind.
        let directory = FilePath(NSTemporaryDirectory()).appending("READMEExamplesTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let store = try SegmentStore(events: [SignedUp.self], directory: directory)
        let tracker = Tracker(store: store)
        let delivery = tracker.records.batch().deliver(to: ConsoleDestination())
        tracker.track(SignedUp(plan: "pro"))
        await tracker.finish()
        try await delivery.execute()  // prints: SignedUp SignedUp(plan: "pro")
    }

    @Event(name: "checkout_started", version: 2)
    struct CheckoutStarted {
        var cartSize: Int
        var coupon: String?
    }

    @Test("Deriving events with @Event")
    func derivingEvents() async throws {
        let tracker = Tracker()
        tracker.track(CheckoutStarted(cartSize: 3, coupon: nil))
        let properties = CheckoutStarted.schema.properties.map(\.name)  // ["cartSize", "coupon"]
        await tracker.finish()

        #expect(properties == ["cartSize", "coupon"])
        #expect(CheckoutStarted.name == "checkout_started")
        #expect(CheckoutStarted.schema.version == 2)
    }
}

extension READMEExamplesTests.SignedUp: BinaryCodable {
    func encode(to encoder: inout BinaryEncoder) {
        encoder.encode(plan)
    }

    init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
        plan = try decoder.decode()
    }
}
