import CollectorEncoding
import EventMacros
import Foundation
import Instrumentation
import Sessions
import StandardContext
import Testing
import Trackers
import TrackingPlans

@Suite("CollectorBatchDecoder: records read back")
struct CollectorBatchDecoderTests {
    @Event(name: "signed_up")
    struct SignedUp: Equatable {
        var plan: String
        var email: Sensitive<String>
        var referrer: String?
        var seats: Int
        var discount: Double
        var trialEndsAt: Date
        var tags: [String]

        static func == (lhs: SignedUp, rhs: SignedUp) -> Bool {
            lhs.plan == rhs.plan && lhs.email.value == rhs.email.value && lhs.referrer == rhs.referrer && lhs.seats == rhs.seats
                && lhs.discount == rhs.discount && lhs.trialEndsAt == rhs.trialEndsAt && lhs.tags == rhs.tags
        }
    }

    @Event(name: "checkout_started", version: 2)
    struct CheckoutStarted: Equatable {
        var cartSize: Int
        var coupon: String?
    }

    enum TraceParentKey: ServiceContextKey {
        typealias Value = String
    }

    /// Extracts `traceparent` as the context's `TraceParentKey`, and injects it back.
    struct TraceParentInstrument: Instrument {
        func extract<Carrier, Extract: Extractor>(
            _ carrier: Carrier,
            into context: inout ServiceContext,
            using extractor: Extract
        ) where Extract.Carrier == Carrier {
            if let traceParent = extractor.extract(key: "traceparent", from: carrier) {
                context[TraceParentKey.self] = traceParent
            }
        }

        func inject<Carrier, Inject: Injector>(
            _ context: ServiceContext,
            into carrier: inout Carrier,
            using injector: Inject
        ) where Inject.Carrier == Carrier {
            if let traceParent = context[TraceParentKey.self] {
                injector.inject(traceParent, forKey: "traceparent", into: &carrier)
            }
        }
    }

    @Test("The collector's fixture decodes and encodes again to its own bytes, byte for byte")
    func fixtureRoundTrip() throws {
        let fixture = try #require(Bundle.module.url(forResource: "collector-batch", withExtension: "json", subdirectory: "Fixtures"))
        let expected = try Data(contentsOf: fixture)
        let plan = try TrackingPlan(schemas: [SignedUp.schema, CheckoutStarted.schema])
        let sut = try CollectorBatchDecoder(plan: plan, events: [SignedUp.self, CheckoutStarted.self], instrument: TraceParentInstrument())
        let encoder = CollectorBatchEncoder(plan: plan, instrument: TraceParentInstrument())

        let decoded = try sut.batch(from: expected)
        let actual = encoder.batch(of: decoded.records)

        #expect(decoded.undecodedRecords.isEmpty)
        #expect(actual.skippedRecords.isEmpty)
        #expect(actual.body?.body == expected)
    }

    @Test("The fixture's records keep their ids, timestamps, events, redelivery and every context value")
    func fixtureRecords() throws {
        let fixture = try #require(Bundle.module.url(forResource: "collector-batch", withExtension: "json", subdirectory: "Fixtures"))
        let body = try Data(contentsOf: fixture)
        let plan = try TrackingPlan(schemas: [SignedUp.schema, CheckoutStarted.schema])
        let sut = try CollectorBatchDecoder(plan: plan, events: [SignedUp.self, CheckoutStarted.self], instrument: TraceParentInstrument())
        let expectedIDs = [UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF"), UUID(uuidString: "00000000-0000-4000-8000-000000000002")]
        let expectedTimestamps = [Date(timeIntervalSince1970: 1_795_442_607.5), Date(timeIntervalSince1970: 1_795_442_608.25)]
        let expectedSignedUp = SignedUp(
            plan: "pro",
            email: Sensitive("ada@example.com"),
            referrer: nil,
            seats: 3,
            discount: 0.25,
            trialEndsAt: Date(timeIntervalSince1970: 1_796_652_207),
            tags: ["beta", "ios"]
        )
        let expectedCheckout = CheckoutStarted(cartSize: 2, coupon: nil)
        let expectedApplication = ApplicationKey.Value(bundleIdentifier: "com.example.shop", version: "2.4.1", build: "418")
        let expectedDevice = DeviceKey.Value(model: "iPhone17,1", formFactor: .phone)
        let expectedOperatingSystem = OperatingSystemKey.Value(name: "iOS", version: "26.1.0")
        let expectedSampleRate = try SampleRate(0.5)
        let expectedSession = UUID(uuidString: "00000000-0000-4000-8000-00000000000A")
        let expectedVendorIdentifier = UUID(uuidString: "00000000-0000-4000-8000-00000000000B")
        let expectedTraceParent = "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
        let expectedLocale = "en-US"

        let actual = try sut.batch(from: body).records

        try #require(actual.count == 2)
        #expect(actual.map(\.id) == expectedIDs.compactMap { $0 })
        #expect(actual.map(\.timestamp) == expectedTimestamps)
        #expect(actual.map(\.isRedelivered) == [false, true])
        #expect(actual[0].event as? SignedUp == expectedSignedUp)
        #expect(actual[1].event as? CheckoutStarted == expectedCheckout)
        #expect(actual[0].context[ApplicationKey.self] == expectedApplication)
        #expect(actual[0].context[DeviceKey.self] == expectedDevice)
        #expect(actual[0].context[LocaleKey.self]?.identifier(.bcp47) == expectedLocale)
        #expect(actual[0].context[NetworkKey.self] == .wifi)
        #expect(actual[0].context[OperatingSystemKey.self] == expectedOperatingSystem)
        #expect(actual[0].context[SampleRateKey.self] == expectedSampleRate)
        #expect(actual[0].context[SessionKey.self] == expectedSession)
        #expect(actual[0].context[VendorIdentifierKey.self].flatMap(actual[0].reveal) == expectedVendorIdentifier)
        #expect(actual[0].context[TraceParentKey.self] == expectedTraceParent)
        #expect(actual[1].context[SessionKey.self] == nil)
        #expect(actual.allSatisfy { $0.sourceLocation == nil && $0.deliveryTag == nil })
    }

    @Test("A decoded record reveals its sensitive values, as a tracked one does")
    func revealsSensitiveValues() throws {
        let plan = try TrackingPlan(schemas: [SignedUp.schema])
        let sut = try CollectorBatchDecoder(plan: plan, events: [SignedUp.self], instrument: NoOpInstrument())
        let body = Data(#"{"records":[{"context":{},"id":"00000000-0000-4000-8000-000000000001","isRedelivered":false,"name":"signed_up","properties":{"discount":1,"email":"ada@example.com","plan":"pro","referrer":"news","seats":3,"tags":[],"trialEndsAt":"2026-12-07T14:03:27.000Z"},"timestamp":"1970-01-01T00:00:00.000Z"}]}"#.utf8)
        let expectedEmail = "ada@example.com"

        let record = try #require(try sut.batch(from: body).records.first)
        let event = try #require(record.event as? SignedUp)

        #expect(record.revealsSensitiveValues)
        #expect(record.reveal(event.email) == expectedEmail)
    }

    @Test("A whole Double, which the body writes without a fraction, reads back as the Double")
    func wholeDouble() throws {
        let plan = try TrackingPlan(schemas: [SignedUp.schema])
        let sut = try CollectorBatchDecoder(plan: plan, events: [SignedUp.self], instrument: NoOpInstrument())
        let body = Data(#"{"records":[{"context":{},"id":"00000000-0000-4000-8000-000000000001","isRedelivered":false,"name":"signed_up","properties":{"discount":1,"email":"a","plan":"pro","referrer":null,"seats":3,"tags":[],"trialEndsAt":"2026-12-07T14:03:27.000Z"},"timestamp":"1970-01-01T00:00:00.000Z"}]}"#.utf8)
        let expected = 1.0

        let event = try #require(try sut.batch(from: body).records.first?.event as? SignedUp)

        #expect(event.discount == expected)
    }

    @Event(name: "measured")
    struct Measured {
        var ratio: Float
        var wide: Double?
        var readings: [Double]
        var big: UInt64
        var scale: Float
        var counts: [String: Int]
    }

    @Test("Floats, whole ones included, optional and array Doubles, a UInt64 past Int64 and a dictionary encode again to the same bytes")
    func numbersRoundTrip() throws {
        let plan = try TrackingPlan(schemas: [Measured.schema])
        let sut = try CollectorBatchDecoder(plan: plan, events: [Measured.self], instrument: NoOpInstrument())
        let encoder = CollectorBatchEncoder(plan: plan, instrument: NoOpInstrument())
        let record = EventRecord(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
            event: Measured(ratio: 0.1, wide: 2, readings: [0, -3, 0.5, 1e20], big: 9_223_372_036_854_777_856, scale: 3, counts: ["a": 1, "b": -2]),
            timestamp: Date(timeIntervalSince1970: 0),
            sourceLocation: nil
        )
        let expected = try #require(encoder.batch(of: [record]).body?.body)
        let expectedRatio: Float = 0.1

        let decoded = try sut.batch(from: expected)
        let actual = encoder.batch(of: decoded.records).body?.body

        #expect(decoded.undecodedRecords.isEmpty)
        #expect((decoded.records.first?.event as? Measured)?.ratio == expectedRatio)
        #expect(actual == expected)
    }

    @Event(name: "scheduled")
    struct Scheduled {
        var at: Date
        var reminders: [Date?]
        var cancelledAt: Date?
        var code: Refined<String, NonEmpty>
    }

    enum NonEmpty: Refinement {
        static var constraints: [Constraint<String>] {
            get throws(InvalidConstraint) { try [.minLength(1)] }
        }
    }

    @Test("Dates, an array of optional dates and a Refined value encode again to the same bytes")
    func datesRoundTrip() throws {
        let plan = try TrackingPlan(schemas: [Scheduled.schema])
        let sut = try CollectorBatchDecoder(plan: plan, events: [Scheduled.self], instrument: NoOpInstrument())
        let encoder = CollectorBatchEncoder(plan: plan, instrument: NoOpInstrument())
        let record = EventRecord(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
            event: Scheduled(
                at: Date(timeIntervalSince1970: -62_135_596_800.123),
                reminders: [Date(timeIntervalSince1970: 1.0009), nil],
                cancelledAt: nil,
                code: try Refined("A1")
            ),
            timestamp: Date(timeIntervalSince1970: 1_795_442_607.999_9),
            sourceLocation: nil
        )
        let expected = try #require(encoder.batch(of: [record]).body?.body)

        let decoded = try sut.batch(from: expected)
        let actual = encoder.batch(of: decoded.records).body?.body

        #expect(decoded.undecodedRecords.isEmpty)
        #expect(actual == expected)
    }

    @Test("The list-of-types initializer takes the Codable list a store takes")
    func codableList() throws {
        let events: [any (Event & Codable).Type] = [SignedUp.self, CheckoutStarted.self]
        let plan = try TrackingPlan(schemas: [SignedUp.schema, CheckoutStarted.schema])
        let body = Data(#"{"records":[{"context":{},"id":"00000000-0000-4000-8000-000000000001","isRedelivered":false,"name":"checkout_started","properties":{"cartSize":2,"coupon":null},"timestamp":"1970-01-01T00:00:00.000Z"}]}"#.utf8)
        let expected = CheckoutStarted(cartSize: 2, coupon: nil)

        let sut = try CollectorBatchDecoder(plan: plan, events: events, instrument: NoOpInstrument())
        let actual = try sut.batch(from: body).records.first?.event as? CheckoutStarted

        #expect(actual == expected)
    }

    @Event(name: "signed_up")
    struct SignedUpAgain {
        var plan: String
    }

    @Test("Two event types of one name throw duplicateEventName, naming both types in order")
    func duplicateEventName() throws {
        let plan = try TrackingPlan(schemas: [SignedUp.schema])
        let expected = CollectorBatchDecoderError.duplicateEventName(
            "signed_up",
            firstType: String(reflecting: SignedUp.self),
            secondType: String(reflecting: SignedUpAgain.self)
        )

        #expect(throws: expected) {
            try CollectorBatchDecoder(plan: plan, events: [SignedUp.self, CheckoutStarted.self, SignedUpAgain.self], instrument: NoOpInstrument())
        }
    }

    // CollectorEncodingModuleExamplesTests, a target of its own, decodes through the list-free
    // initializer; this one pins that it reads the discovered events.
    @Test("The list-free initializer takes every discovered event, so it throws for this target's events, several suites of which declare signed_up")
    func discoveredEvents() throws {
        let plan = try TrackingPlan(schemas: [SignedUp.schema])

        #expect(throws: CollectorBatchDecoderError.self) {
            try CollectorBatchDecoder(plan: plan, instrument: NoOpInstrument())
        }
    }

    @Test("Event types of different names don't throw, whatever the plan holds")
    func distinctNames() throws {
        let plan = try TrackingPlan(schemas: [])

        let sut = try CollectorBatchDecoder(plan: plan, events: [SignedUp.self, CheckoutStarted.self], instrument: NoOpInstrument())
        let actual = try sut.batch(from: Data(#"{"records":[]}"#.utf8))

        #expect(actual.records.isEmpty)
        #expect(actual.undecodedRecords.isEmpty)
    }
}
