import CollectorEncoding
import EventMacros
import Foundation
import HTTPDestinations
import HTTPTypes
import Instrumentation
import Synchronization
import Testing
import TrackingPlans

@Suite("CollectorBatchEncoder: skipped records", .timeLimit(.minutes(1)))
struct CollectorSkippedRecordTests {
    @Event(name: "checkout_started", version: 2)
    struct CheckoutStarted {
        var cartSize: Int
    }

    @Event(name: "screen_viewed")
    struct ScreenViewed {
        var screen: String
    }

    @Event(name: "measured")
    struct Measured {
        var value: Double
    }

    struct HandWritten: Event {
        var plan: String
    }

    /// Answers every request with 202 Accepted, and counts the requests it was sent.
    final class TransportDouble: HTTPTransport {
        let sentCount = Mutex(0)

        func send(_ request: HTTPRequest, body: Data) async throws(HTTPTransportError) -> HTTPResponse {
            sentCount.withLock { $0 += 1 }
            return HTTPResponse(status: .accepted)
        }
    }

    @Test("A record whose event the plan doesn't describe is left out, and the records around it are sent in order")
    func unknownEventInTheMiddle() throws {
        let sut = CollectorBatchEncoder(plan: TrackingPlan(schemas: [CheckoutStarted.schema]), instrument: NoOpInstrument())
        let skippedID = try #require(UUID(uuidString: "00000000-0000-4000-8000-000000000002"))
        let batch = [
            EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil),
            EventRecord(id: skippedID, event: ScreenViewed(screen: "Home"), timestamp: Date(timeIntervalSince1970: 1), sourceLocation: nil),
            EventRecord(event: CheckoutStarted(cartSize: 3), timestamp: Date(timeIntervalSince1970: 2), sourceLocation: nil),
        ]
        let expectedSizes: [Int] = [1, 3]
        let expectedSkipped = [SkippedRecord(recordID: skippedID, eventName: "screen_viewed", schemaVersion: 1, reason: .unknownEvent(name: "screen_viewed", version: 1))]

        let actual = sut.batch(of: batch)

        let body = try #require(actual.body).body
        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let records = try #require(object["records"] as? [[String: Any]])
        let actualSizes = records.compactMap { ($0["properties"] as? [String: Any])?["cartSize"] as? Int }
        #expect(actualSizes == expectedSizes)
        #expect(actual.skippedRecords == expectedSkipped)
    }

    @Test("encode sends the other records of a batch with an unknown event, the same bytes as a batch without it")
    func encodeLeavesTheRecordOut() throws {
        let sut = CollectorBatchEncoder(plan: TrackingPlan(schemas: [CheckoutStarted.schema]), instrument: NoOpInstrument())
        let first = EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)
        let unknown = EventRecord(event: ScreenViewed(screen: "Home"), timestamp: Date(timeIntervalSince1970: 1), sourceLocation: nil)
        let last = EventRecord(event: CheckoutStarted(cartSize: 3), timestamp: Date(timeIntervalSince1970: 2), sourceLocation: nil)
        let expected = try sut.encode([first, last])

        let actual = try sut.encode([first, unknown, last])

        #expect(actual == expected)
    }

    @Test("A record whose event isn't BinaryCodable is left out as notBinaryCodable, not the batch")
    func notBinaryCodableInTheMiddle() throws {
        let handWritten = EventSchema(name: "HandWritten", version: 1, consentCategory: .analytics, properties: [EventSchema.Property(name: "plan", typeName: "String", isOptional: false)])
        let sut = CollectorBatchEncoder(plan: TrackingPlan(schemas: [CheckoutStarted.schema, handWritten]), instrument: NoOpInstrument())
        let skipped = EventRecord(event: HandWritten(plan: "pro"), timestamp: Date(timeIntervalSince1970: 1), sourceLocation: nil)
        let batch = [
            EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil),
            skipped,
            EventRecord(event: CheckoutStarted(cartSize: 3), timestamp: Date(timeIntervalSince1970: 2), sourceLocation: nil),
        ]
        let expectedSkipped = [SkippedRecord(recordID: skipped.id, eventName: "HandWritten", schemaVersion: 1, reason: .notBinaryCodable(name: "HandWritten"))]
        let expectedBody = try sut.encode([batch[0], batch[2]])

        let actual = sut.batch(of: batch)

        #expect(actual.body == expectedBody)
        #expect(actual.skippedRecords == expectedSkipped)
    }

    @Test("A record holding a value JSON can't hold is left out as unrepresentableValue, not the batch")
    func unrepresentableValueInTheMiddle() throws {
        let sut = CollectorBatchEncoder(plan: TrackingPlan(schemas: [CheckoutStarted.schema, Measured.schema]), instrument: NoOpInstrument())
        let skipped = EventRecord(event: Measured(value: .nan), timestamp: Date(timeIntervalSince1970: 1), sourceLocation: nil)
        let batch = [
            EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil),
            skipped,
            EventRecord(event: CheckoutStarted(cartSize: 3), timestamp: Date(timeIntervalSince1970: 2), sourceLocation: nil),
        ]
        let expectedSkipped = [SkippedRecord(recordID: skipped.id, eventName: "measured", schemaVersion: 1, reason: .unrepresentableValue(event: "measured", property: "value"))]
        let expectedBody = try sut.encode([batch[0], batch[2]])

        let actual = sut.batch(of: batch)

        #expect(actual.body == expectedBody)
        #expect(actual.skippedRecords == expectedSkipped)
    }

    @Test("A batch whose every record is skipped has no body, and encode throws the first record's reason")
    func everyRecordSkipped() {
        let sut = CollectorBatchEncoder(plan: TrackingPlan(schemas: []), instrument: NoOpInstrument())
        let batch = [
            EventRecord(event: ScreenViewed(screen: "Home"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil),
            EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 1), sourceLocation: nil),
        ]
        let expectedReasons: [CollectorEncodingError] = [.unknownEvent(name: "screen_viewed", version: 1), .unknownEvent(name: "checkout_started", version: 2)]
        let expectedVersions: [Int] = [1, 2]
        let expectedError = CollectorEncodingError.unknownEvent(name: "screen_viewed", version: 1)

        let actual = sut.batch(of: batch)

        #expect(actual.body == nil)
        #expect(actual.skippedRecords.map(\.reason) == expectedReasons)
        #expect(actual.skippedRecords.map(\.schemaVersion) == expectedVersions)
        #expect(throws: expectedError) {
            try sut.encode(batch)
        }
    }

    @Test("An empty batch has a body of no records and skips nothing")
    func emptyBatch() {
        let sut = CollectorBatchEncoder(plan: TrackingPlan(schemas: []), instrument: NoOpInstrument())
        let expected = #"{"records":[]}"#

        let actual = sut.batch(of: [])

        #expect(actual.body.map { String(decoding: $0.body, as: UTF8.self) } == expected)
        #expect(actual.skippedRecords.isEmpty)
    }

    @Test("HTTPDestination sends nothing for a batch whose every record is skipped")
    func nothingSent() async throws {
        let encoder = CollectorBatchEncoder(plan: TrackingPlan(schemas: []), instrument: NoOpInstrument())
        let transport = TransportDouble()
        let sut = HTTPDestination(
            endpoint: try #require(URL(string: "https://collector.example.com/v1/batches")),
            instrument: NoOpInstrument(),
            transport: transport,
            encoder: encoder
        )
        let record = EventRecord(event: ScreenViewed(screen: "Home"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)
        let expected = 0

        await sut.receive([record])

        let actual = transport.sentCount.withLock { $0 }
        #expect(actual == expected)
    }
}
