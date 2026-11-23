// The README's examples, verbatim, so the README cannot drift from the code.

import EventMacros
import Foundation
import Instrumentation
import SystemPackage
import Traffluent
import Testing
import TrackerTesting
import TrackingPlans

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

    @Test("Testing what your code tracks")
    func signingUpTracksThePlan() async {
        let tracked = await withRecordingTracker {
            Tracker.current.track(SignedUp(plan: "pro"))
        }
        #expect(tracked.events(of: SignedUp.self) == [SignedUp(plan: "pro")])
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

    enum ExperimentKey: ServiceContextKey {
        typealias Value = String
    }

    @Test("Context and enrichers")
    func contextAndEnrichers() async throws {
        let experiment = Enricher { context in
            context[ExperimentKey.self] = "new-checkout"
        }
        let tracker = Tracker(enrichers: [experiment])
        tracker.track(SignedUp(plan: "pro"))  // its record's context[ExperimentKey.self] is "new-checkout"
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

    @Test("App lifecycle")
    func appLifecycle() async throws {
        // The README's store uses the default directory; this one uses a scratch directory so the
        // test leaves nothing behind.
        let directory = FilePath(NSTemporaryDirectory()).appending("READMEExamplesTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let store = try SegmentStore(events: [ApplicationOpened.self, ApplicationBackgrounded.self, SignedUp.self], directory: directory)
        let tracker = Tracker(store: store)
        // In the application delegate's application(_:didFinishLaunchingWithOptions:), kept beside the tracker:
        let lifecycle = tracker.trackLifecycle(
            kinds: [.installed, .updated, .opened, .backgrounded],
            versionStore: FileVersionStore(directory: store.directory)
        )
        let delivery = tracker.records
            .batch(strategy: .either(.count(20), .time(interval: .seconds(30), clock: ContinuousClock()), .lifecycle))
            .deliver(to: ConsoleDestination())
        await lifecycle.finish()
        await tracker.finish()
        try await delivery.execute()  // prints: ApplicationOpened ApplicationOpened(fromBackground: false)
    }

    @Test("Sessions")
    func sessions() async throws {
        let tracker = Tracker(enrichers: [.sessions(timeout: .seconds(30 * 60))])
        tracker.track(SignedUp(plan: "pro"))  // its record's context[SessionKey.self] is the session's UUID
        await tracker.finish()

        var records = tracker.records.makeAsyncIterator()
        let started = try #require(await records.next())
        let signedUp = try #require(await records.next())
        #expect(started.event is SessionStarted)
        #expect(signedUp.context[SessionKey.self] != nil)
        #expect(signedUp.context[SessionKey.self] == started.context[SessionKey.self])
    }

    @Test("Standard context")
    func standardContext() async throws {
        let tracker = Tracker(enrichers: [.application(), .device(), .operatingSystem(), .locale(), .network()])
        tracker.track(SignedUp(plan: "pro"))  // its record's context[OperatingSystemKey.self]?.name is "iOS" on an iPhone
        await tracker.finish()

        var records = tracker.records.makeAsyncIterator()
        let record = try #require(await records.next())
        #expect(record.context[ApplicationKey.self] == ApplicationKey.Value.current)
        #expect(record.context[OperatingSystemKey.self] == OperatingSystemKey.Value.current)
        #expect(record.context[DeviceKey.self] == DeviceKey.Value.current)
        #expect(record.context[LocaleKey.self]?.identifier == Locale.current.identifier)
    }

    struct Scrolled: Event {
        var offset: Int
    }

    @Test("Sampling")
    func sampling() async throws {
        let tracker = Tracker(
            enrichers: [.sessions()],
            samplers: [.events(of: Scrolled.self, rate: 0.1), .sessions(rate: 0.5)]
        )
        tracker.track(Scrolled(offset: 120))  // if kept, its record's context[SampleRateKey.self]?.value is 0.05
        await tracker.finish()

        for await record in tracker.records where record.event is Scrolled {
            #expect(record.context[SampleRateKey.self]?.value == 0.05)
        }
    }

    @Test("Sampling: a fixed seed and the drops")
    func samplingSeedAndDrops() async {
        let tracker = Tracker(samplers: [.events(of: Scrolled.self, rate: 0.1)], samplingSeed: 42)
        for offset in 0 ..< 100 {
            tracker.track(Scrolled(offset: offset))
        }
        await tracker.finish()
        for await report in tracker.samplingDropReports {
            print(report)  // Scrolled: 89 sampled out
            #expect(report.description == "Scrolled: 89 sampled out")
        }
    }

    @Test("Standard context on a server")
    func standardContextOnAServer() async throws {
        let tracker = Tracker(enrichers: [
            .application(ApplicationKey.Value(bundleIdentifier: "com.example.server", version: "1.2.0", build: "42")),
            .operatingSystem(),
        ])
        tracker.track(SignedUp(plan: "pro"))
        await tracker.finish()

        var records = tracker.records.makeAsyncIterator()
        let record = try #require(await records.next())
        #expect(record.context[ApplicationKey.self]?.version == "1.2.0")
        #expect(record.context[DeviceKey.self] == nil)
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

    enum CouponCode: Refinement {
        static let constraints: [Constraint<String>] = [.pattern("^[A-Z0-9]{6}$", example: "SPRING")]
    }

    @Event(name: "search_performed")
    struct SearchPerformed {
        @Constrained(.minLength(1), .maxLength(200))
        var query: String
        @Constrained(.minimum(0))
        var resultCount: Int
        var coupon: Refined<String, CouponCode>?
    }

    @Test("Constraining properties")
    func constrainingProperties() async throws {
        let coupon = try? Refined<String, CouponCode>(checked: "spring")  // nil: UnsatisfiedConstraint.pattern
        let tracker = Tracker()
        tracker.track(SearchPerformed(query: "", resultCount: 3, coupon: Refined("SPRING")))
        await tracker.finish()
        for await report in tracker.rejectionReports {
            print(report)  // search_performed: "query" breaks minLength 1 (1 rejected)
        }

        #expect(coupon == nil)
        #expect(throws: UnsatisfiedConstraint.pattern) { try Refined<String, CouponCode>(checked: "spring") }
        var reports = tracker.rejectionReports.makeAsyncIterator()
        #expect(await reports.next() == nil)
    }

    @Test("Constraining properties: the report")
    func constrainingPropertiesReport() async {
        let tracker = Tracker()
        let expected = #"search_performed: "query" breaks minLength 1 (1 rejected)"#

        tracker.track(SearchPerformed(query: "", resultCount: 3, coupon: Refined("SPRING")))
        await tracker.finish()

        var reports = tracker.rejectionReports.makeAsyncIterator()
        #expect(await reports.next()?.description == expected)
    }

    @Test("Exporting a tracking plan")
    func exportingATrackingPlan() {
        let plan = TrackingPlan(schemas: [CheckoutStarted.schema])
        let paths = plan.files.map(\.path)
        // ["tracking-plan.json", "checkout_started.v2.schema.json", "checkout_started.v2.example.json"]

        #expect(paths == ["tracking-plan.json", "checkout_started.v2.schema.json", "checkout_started.v2.example.json"])
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

// The README states that `SignedUp` is `Equatable` for its testing example.
extension READMEExamplesTests.SignedUp: Equatable {}
