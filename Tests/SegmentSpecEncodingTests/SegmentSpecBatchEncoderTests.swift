import EventMacros
import Foundation
import Instrumentation
import SegmentSpecEncoding
import Sessions
import StandardContext
import Testing
import Trackers
import TrackingPlans

// Private: its events share their names with other events of this test target, and @Event
// leaves a private type's events out of the link check of names (DefiningEvents, Limits).
@Suite("SegmentSpecBatchEncoder")
private struct SegmentSpecBatchEncoderTests {
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

    @Event(name: "opened")
    struct Opened {}

    @Event(name: "note_added")
    struct NoteAdded {
        var text: String
    }

    enum TraceParentKey: ServiceContextKey {
        typealias Value = String
    }

    // The batch call of Segment's HTTP Tracking API
    // (https://segment.com/docs/connections/sources/catalog/libraries/server/http-api/, "Batch"): an
    // object of one member, "batch", an array of track calls, each {"anonymousId", "context",
    // "event", "messageId", "properties", "timestamp", "type": "track"}. The first record reveals
    // its email, which still isn't sent; the second has a session but no standard context.
    @Test("A hand-worked batch encodes to Segment's batch call, byte for byte, without its Sensitive email")
    func handWorkedBatch() throws {
        let plan = try TrackingPlan(schemas: [SignedUp.schema, CheckoutStarted.schema])
        let sut = SegmentSpecBatchEncoder(plan: plan)
        var context = ServiceContext.topLevel
        context[ApplicationKey.self] = ApplicationKey.Value(bundleIdentifier: "com.example.shop", version: "2.4.1", build: "418")
        context[DeviceKey.self] = DeviceKey.Value(model: "iPhone17,1", formFactor: .phone)
        context[LocaleKey.self] = Locale(identifier: "en_US")
        context[NetworkKey.self] = .wifi
        context[OperatingSystemKey.self] = OperatingSystemKey.Value(name: "iOS", version: "26.1.0")
        context[SampleRateKey.self] = try SampleRate(0.5)
        context[SessionKey.self] = UUID(uuidString: "01A208B7-E840-7A3E-8B4D-5C6E7F801234")!
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
        var secondContext = ServiceContext.topLevel
        secondContext[SessionKey.self] = UUID(uuidString: "00000000-0000-4000-8000-00000000000C")!
        let second = EventRecord(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!,
            event: CheckoutStarted(cartSize: 2, coupon: nil),
            timestamp: Date(timeIntervalSince1970: 1_795_442_608.25),
            sourceLocation: nil,
            context: secondContext,
            isRedelivered: true
        )
        let expected = #"{"batch":[{"anonymousId":"01a208b7-e840-7a3e-8b4d-5c6e7f801234","context":{"app":{"build":"418","namespace":"com.example.shop","version":"2.4.1"},"device":{"model":"iPhone17,1","type":"ios"},"ip":"0.0.0.0","locale":"en-US","network":{"cellular":false,"wifi":true},"os":{"name":"iOS","version":"26.1.0"}},"event":"signed_up","messageId":"6f9619ff-8b86-d011-b42d-00c04fc964ff","properties":{"discount":0.25,"plan":"pro","referrer":null,"seats":3,"tags":["beta","ios"],"trialEndsAt":"2026-12-07T14:03:27.000Z"},"timestamp":"2026-11-23T14:03:27.500Z","type":"track"},{"anonymousId":"00000000-0000-4000-8000-00000000000c","context":{"ip":"0.0.0.0"},"event":"checkout_started","messageId":"00000000-0000-4000-8000-000000000002","properties":{"cartSize":2,"coupon":null},"timestamp":"2026-11-23T14:03:28.250Z","type":"track"}]}"#
        let expectedContentType = "application/json"

        let actual = try #require(sut.requests(for: [first, second]).requests.first).body

        #expect(String(decoding: actual.body, as: UTF8.self) == expected)
        #expect(actual.contentType == expectedContentType)
    }

    // The input SegmentSpecBatchEncoderPropertyTests failed on (TRAF-138): one record without a
    // session whose text is the one scalar U+FEFF, which JSONSerialization reads back as "".
    @Test("A text of exactly U+FEFF is sent as its three UTF-8 bytes, EF BB BF, as it is")
    func byteOrderMarkText() throws {
        let sut = SegmentSpecBatchEncoder(plan: try TrackingPlan(schemas: [NoteAdded.schema]))
        let record = EventRecord(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
            event: NoteAdded(text: "\u{FEFF}"),
            timestamp: Date(timeIntervalSince1970: 1_795_442_607),
            sourceLocation: nil
        )
        let expected: [UInt8] = Array(#"{"batch":[{"anonymousId":"00000000-0000-4000-8000-000000000001","context":{"ip":"0.0.0.0"},"event":"note_added","messageId":"00000000-0000-4000-8000-000000000001","properties":{"text":""#.utf8)
            + [0xEF, 0xBB, 0xBF]
            + Array(#""},"timestamp":"2026-11-23T14:03:27.000Z","type":"track"}]}"#.utf8)

        let actual = try #require(sut.requests(for: [record]).requests.first).body.body

        #expect(Array(actual) == expected)
    }

    @Test("A redelivered record encodes with the messageId it was first sent with")
    func redelivered() throws {
        let plan = try TrackingPlan(schemas: [CheckoutStarted.schema])
        let sut = SegmentSpecBatchEncoder(plan: plan)
        var context = ServiceContext.topLevel
        context[SessionKey.self] = UUID(uuidString: "01A208B7-E840-7A3E-8B4D-5C6E7F801234")!
        let firstDelivery = EventRecord(
            id: UUID(uuidString: "2B4C6D8E-1A3F-4B5C-9D7E-0F1A2B3C4D5E")!,
            event: CheckoutStarted(cartSize: 1, coupon: "SPRING"),
            timestamp: Date(timeIntervalSince1970: 1_795_442_607),
            sourceLocation: nil,
            context: context
        )
        // As a delivery hands it over again: the same identifier, marked redelivered.
        let redelivery = EventRecord(
            id: firstDelivery.id,
            event: firstDelivery.event,
            timestamp: firstDelivery.timestamp,
            sourceLocation: nil,
            context: context,
            isRedelivered: true
        )
        let expected = try #require(sut.requests(for: [firstDelivery]).requests.first).body

        let actual = try #require(sut.requests(for: [redelivery]).requests.first).body

        #expect(actual == expected)
    }

    @Test("Calls are encoded in the batch's order, oldest first")
    func order() throws {
        let plan = try TrackingPlan(schemas: [CheckoutStarted.schema])
        let sut = SegmentSpecBatchEncoder(plan: plan)
        var context = ServiceContext.topLevel
        context[SessionKey.self] = UUID()
        let batch = [3, 1, 2].map { size in
            EventRecord(event: CheckoutStarted(cartSize: size, coupon: nil), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil, context: context)
        }
        let expected: [Int] = [3, 1, 2]

        let body = try #require(sut.requests(for: batch).requests.first).body.body
        let calls = try #require((try JSONSerialization.jsonObject(with: body) as? [String: Any])?["batch"] as? [[String: Any]])
        let actual = calls.compactMap { ($0["properties"] as? [String: Any])?["cartSize"] as? Int }

        #expect(actual == expected)
    }

    @Test("Every call is a track call: type is \"track\", and event is the event's name as it is")
    func trackCall() throws {
        let sut = SegmentSpecBatchEncoder(plan: try TrackingPlan(schemas: [CheckoutStarted.schema, Opened.schema]))
        let batch = [
            EventRecord(event: CheckoutStarted(cartSize: 1, coupon: nil), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil),
            EventRecord(event: Opened(), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil),
        ]
        let expectedTypes: [String?] = ["track", "track"]
        let expectedEvents: [String?] = ["checkout_started", "opened"]

        let body = try #require(sut.requests(for: batch).requests.first).body.body
        let calls = try #require((try JSONSerialization.jsonObject(with: body) as? [String: Any])?["batch"] as? [[String: Any]])

        #expect(calls.map { $0["type"] as? String } == expectedTypes)
        #expect(calls.map { $0["event"] as? String } == expectedEvents)
    }

    @Test("timestamp is ISO 8601 in UTC with milliseconds, rounded down, in the proleptic Gregorian calendar from year 1 to 9999", arguments: [
        (0.0, "1970-01-01T00:00:00.000Z"), (0.0009, "1970-01-01T00:00:00.000Z"), (-0.5, "1969-12-31T23:59:59.500Z"),
        (1_795_442_607.125, "2026-11-23T14:03:27.125Z"), (-62_135_596_800, "0001-01-01T00:00:00.000Z"),
        (-12_219_379_200, "1582-10-14T00:00:00.000Z"), (-12_219_292_800, "1582-10-15T00:00:00.000Z"),
        (253_402_300_799.5, "9999-12-31T23:59:59.500Z"),
    ])
    func timestamp(seconds: Double, expected: String) throws {
        let plan = try TrackingPlan(schemas: [CheckoutStarted.schema])
        let sut = SegmentSpecBatchEncoder(plan: plan)
        let record = EventRecord(event: CheckoutStarted(cartSize: 1, coupon: nil), timestamp: Date(timeIntervalSince1970: seconds), sourceLocation: nil)

        let body = try #require(sut.requests(for: [record]).requests.first).body.body
        let call = try #require(((try JSONSerialization.jsonObject(with: body) as? [String: Any])?["batch"] as? [[String: Any]])?.first)
        let actual = call["timestamp"] as? String

        #expect(actual == expected)
    }

    @Test("A Sensitive property is left out, whether or not the record reveals it", arguments: [true, false])
    func sensitiveNeverSent(reveals: Bool) throws {
        let plan = try TrackingPlan(schemas: [SignedUp.schema])
        let sut = SegmentSpecBatchEncoder(plan: plan)
        var context = ServiceContext.topLevel
        context[SessionKey.self] = UUID(uuidString: "00000000-0000-4000-8000-00000000000A")!
        var record = EventRecord(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
            event: SignedUp(plan: "pro", email: Sensitive("ada@example.com"), referrer: "ad", seats: 1, discount: 0, trialEndsAt: Date(timeIntervalSince1970: 0), tags: []),
            timestamp: Date(timeIntervalSince1970: 1_795_442_607),
            sourceLocation: nil,
            context: context
        )
        record.revealsSensitiveValues = reveals
        let expectedKeys = ["discount", "plan", "referrer", "seats", "tags", "trialEndsAt"]

        let body = try #require(sut.requests(for: [record]).requests.first).body.body
        let call = try #require(((try JSONSerialization.jsonObject(with: body) as? [String: Any])?["batch"] as? [[String: Any]])?.first)
        let actual = try #require(call["properties"] as? [String: Any]).keys.sorted()

        #expect(actual == expectedKeys)
        #expect(!String(decoding: body, as: UTF8.self).contains("ada@example.com"))
    }

    @Test("An event without properties is sent with empty properties and only the members the encoder writes")
    func emptyProperties() throws {
        let sut = SegmentSpecBatchEncoder(plan: try TrackingPlan(schemas: [Opened.schema]))
        let record = EventRecord(id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!, event: Opened(), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expected = #"{"batch":[{"anonymousId":"00000000-0000-4000-8000-000000000001","context":{"ip":"0.0.0.0"},"event":"opened","messageId":"00000000-0000-4000-8000-000000000001","properties":{},"timestamp":"2026-11-23T14:03:27.000Z","type":"track"}]}"#

        let actual = try #require(sut.requests(for: [record]).requests.first).body

        #expect(String(decoding: actual.body, as: UTF8.self) == expected)
    }
}
