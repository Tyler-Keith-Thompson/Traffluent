import CollectorEncoding
import EventMacros
import Foundation
import HTTPDestinations
import HTTPTypes
import Instrumentation
import Sessions
import StandardContext
import Synchronization
import Testing
import Trackers
import TrackingPlans

// Private: its events share their names with other events of this test target, and @Event
// leaves a private type's events out of the link check of names (DefiningEvents, Limits).
@Suite("CollectorBatchEncoder")
private struct CollectorBatchEncoderTests {
    @Event(name: "signed_up")
    struct SignedUp {
        var plan: String
        var email: Sensitive<String>
        var referrer: String?
        var seats: Int
        var discount: Double
        var trialEndsAt: Date
        var tags: [String]
    }

    @Event(name: "checkout_started", version: 2)
    struct CheckoutStarted {
        var cartSize: Int
        var coupon: String?
    }

    enum TraceParentKey: ServiceContextKey {
        typealias Value = String
    }

    /// Injects a context's `TraceParentKey` as `traceparent`, and nothing for a context without one.
    struct TraceParentInstrument: Instrument {
        func extract<Carrier, Extract: Extractor>(
            _ carrier: Carrier,
            into context: inout ServiceContext,
            using extractor: Extract
        ) where Extract.Carrier == Carrier {}

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

    struct SentRequest: Sendable {
        var request: HTTPRequest
        var body: Data
    }

    /// Answers every request with 202 Accepted, and keeps each request it was sent.
    final class TransportDouble: HTTPTransport {
        let sent = Mutex<[SentRequest]>([])

        func send(_ request: HTTPRequest, body: Data) async throws(HTTPTransportError) -> HTTPTransportResponse {
            sent.withLock { $0.append(SentRequest(request: request, body: body)) }
            return HTTPTransportResponse(head: HTTPResponse(status: .accepted), body: Data())
        }
    }

    // The bytes of Fixtures/collector-batch.json, which TraffluentCollector's ingest
    // tests decode: CollectorFixtureTests checks the file holds them.
    @Test("A hand-worked batch encodes every member of each record, keys sorted and no whitespace")
    func handWorkedBatch() throws {
        let plan = try TrackingPlan(schemas: [SignedUp.schema, CheckoutStarted.schema])
        let sut = CollectorBatchEncoder(plan: plan, instrument: TraceParentInstrument())
        var context = ServiceContext.topLevel
        context[ApplicationKey.self] = ApplicationKey.Value(bundleIdentifier: "com.example.shop", version: "2.4.1", build: "418")
        context[DeviceKey.self] = DeviceKey.Value(model: "iPhone17,1", formFactor: .phone)
        context[LocaleKey.self] = Locale(identifier: "en_US")
        context[NetworkKey.self] = .wifi
        context[OperatingSystemKey.self] = OperatingSystemKey.Value(name: "iOS", version: "26.1.0")
        context[SampleRateKey.self] = try SampleRate(0.5)
        context[SessionKey.self] = UUID(uuidString: "00000000-0000-4000-8000-00000000000A")!
        context[VendorIdentifierKey.self] = Sensitive(UUID(uuidString: "00000000-0000-4000-8000-00000000000B")!)
        context[TraceParentKey.self] = "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
        let signedUp = SignedUp(
            plan: "pro",
            email: Sensitive("ada@example.com"),
            referrer: nil,
            seats: 3,
            discount: 0.25,
            trialEndsAt: Date(timeIntervalSince1970: 1_796_652_207),
            tags: ["beta", "ios"]
        )
        var first = EventRecord(
            id: UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!,
            event: signedUp,
            timestamp: Date(timeIntervalSince1970: 1_795_442_607.5),
            sourceLocation: nil,
            context: context
        )
        first.revealsSensitiveValues = true
        let second = EventRecord(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!,
            event: CheckoutStarted(cartSize: 2, coupon: nil),
            timestamp: Date(timeIntervalSince1970: 1_795_442_608.25),
            sourceLocation: nil,
            isRedelivered: true
        )
        let expected = #"{"records":[{"context":{"application":{"build":"418","bundleIdentifier":"com.example.shop","version":"2.4.1"},"device":{"formFactor":"phone","model":"iPhone17,1"},"locale":"en-US","network":"wifi","operatingSystem":{"name":"iOS","version":"26.1.0"},"sampleRate":0.5,"session":"00000000-0000-4000-8000-00000000000A","trace":{"traceparent":"00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"},"vendorIdentifier":"00000000-0000-4000-8000-00000000000B"},"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","isRedelivered":false,"name":"signed_up","properties":{"discount":0.25,"email":"ada@example.com","plan":"pro","referrer":null,"seats":3,"tags":["beta","ios"],"trialEndsAt":"2026-12-07T14:03:27.000Z"},"timestamp":"2026-11-23T14:03:27.500Z"},{"context":{},"id":"00000000-0000-4000-8000-000000000002","isRedelivered":true,"name":"checkout_started","properties":{"cartSize":2,"coupon":null},"timestamp":"2026-11-23T14:03:28.250Z"}]}"#
        let expectedContentType = "application/json"

        let actual = try #require(sut.batch(of: [first, second]).body)

        #expect(String(decoding: actual.body, as: UTF8.self) == expected)
        #expect(actual.contentType == expectedContentType)
    }

    @Test("A redelivered record encodes with the identifier it was first sent with and isRedelivered true")
    func redelivered() throws {
        let plan = try TrackingPlan(schemas: [CheckoutStarted.schema])
        let sut = CollectorBatchEncoder(plan: plan, instrument: NoOpInstrument())
        let id = UUID(uuidString: "2B4C6D8E-1A3F-4B5C-9D7E-0F1A2B3C4D5E")!
        let firstDelivery = EventRecord(
            id: id,
            event: CheckoutStarted(cartSize: 1, coupon: "SPRING"),
            timestamp: Date(timeIntervalSince1970: 1_795_442_607),
            sourceLocation: nil
        )
        // As a store remakes it in a later run: the same identifier, marked redelivered.
        let redelivery = EventRecord(
            id: firstDelivery.id,
            event: firstDelivery.event,
            timestamp: firstDelivery.timestamp,
            sourceLocation: nil,
            isRedelivered: true
        )
        let expected = #"{"records":[{"context":{},"id":"2B4C6D8E-1A3F-4B5C-9D7E-0F1A2B3C4D5E","isRedelivered":true,"name":"checkout_started","properties":{"cartSize":1,"coupon":"SPRING"},"timestamp":"2026-11-23T14:03:27.000Z"}]}"#

        let actual = try #require(sut.batch(of: [redelivery]).body)

        #expect(String(decoding: actual.body, as: UTF8.self) == expected)
    }

    @Test("Records are encoded in the batch's order, oldest first")
    func order() throws {
        let plan = try TrackingPlan(schemas: [CheckoutStarted.schema])
        let sut = CollectorBatchEncoder(plan: plan, instrument: NoOpInstrument())
        let batch = [3, 1, 2].map { size in
            EventRecord(event: CheckoutStarted(cartSize: size, coupon: nil), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        }
        let expected: [Int] = [3, 1, 2]

        let body = try #require(sut.batch(of: batch).body).body
        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let records = try #require(object["records"] as? [[String: Any]])
        let actual = records.compactMap { ($0["properties"] as? [String: Any])?["cartSize"] as? Int }

        #expect(actual == expected)
    }

    @Test("An empty batch is an empty records array")
    func emptyBatch() throws {
        let sut = CollectorBatchEncoder(plan: try TrackingPlan(schemas: []), instrument: NoOpInstrument())
        let expected = #"{"records":[]}"#

        let actual = try #require(sut.batch(of: []).body)

        #expect(String(decoding: actual.body, as: UTF8.self) == expected)
    }

    @Test("A timestamp is ISO 8601 in UTC with milliseconds, whole seconds included")
    func timestamp() throws {
        let plan = try TrackingPlan(schemas: [CheckoutStarted.schema])
        let sut = CollectorBatchEncoder(plan: plan, instrument: NoOpInstrument())
        let record = EventRecord(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
            event: CheckoutStarted(cartSize: 1, coupon: nil),
            timestamp: Date(timeIntervalSince1970: 0.125),
            sourceLocation: nil
        )
        let expected = #"{"records":[{"context":{},"id":"00000000-0000-4000-8000-000000000001","isRedelivered":false,"name":"checkout_started","properties":{"cartSize":1,"coupon":null},"timestamp":"1970-01-01T00:00:00.125Z"}]}"#

        let actual = try #require(sut.batch(of: [record]).body)

        #expect(String(decoding: actual.body, as: UTF8.self) == expected)
    }

    @Test("A timestamp before the Gregorian reform of 1582 is in the proleptic Gregorian calendar, as ISO 8601 counts")
    func timestampBeforeReform() throws {
        let plan = try TrackingPlan(schemas: [CheckoutStarted.schema])
        let sut = CollectorBatchEncoder(plan: plan, instrument: NoOpInstrument())
        let record = EventRecord(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
            event: CheckoutStarted(cartSize: 1, coupon: nil),
            timestamp: Date(timeIntervalSince1970: -62_135_596_800),
            sourceLocation: nil
        )
        let expected = #"{"records":[{"context":{},"id":"00000000-0000-4000-8000-000000000001","isRedelivered":false,"name":"checkout_started","properties":{"cartSize":1,"coupon":null},"timestamp":"0001-01-01T00:00:00.000Z"}]}"#

        let actual = try #require(sut.batch(of: [record]).body)

        #expect(String(decoding: actual.body, as: UTF8.self) == expected)
    }

    @Test("HTTPDestination sends the encoder's body with its content type")
    func throughHTTPDestination() async throws {
        let plan = try TrackingPlan(schemas: [CheckoutStarted.schema])
        let encoder = CollectorBatchEncoder(plan: plan, instrument: NoOpInstrument())
        let record = EventRecord(event: CheckoutStarted(cartSize: 4, coupon: nil), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expected = try #require(encoder.batch(of: [record]).body)
        let transport = TransportDouble()
        let sut = HTTPDestination(
            endpoint: try #require(URL(string: "https://collector.example.com/v1/batches")),
            headerFields: [.authorization: "Bearer k3y"],
            instrument: NoOpInstrument(),
            transport: transport,
            encoder: encoder
        )
        let expectedAuthorization = "Bearer k3y"

        await sut.receive([record])

        let actual = try #require(transport.sent.withLock { $0.first })
        #expect(actual.body == expected.body)
        #expect(actual.request.headerFields[.contentType] == expected.contentType)
        #expect(actual.request.headerFields[.authorization] == expectedAuthorization)
    }
}
