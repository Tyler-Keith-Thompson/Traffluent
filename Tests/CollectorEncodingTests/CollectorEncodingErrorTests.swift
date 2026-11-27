import CollectorEncoding
import EventMacros
import Foundation
import Instrumentation
import Testing
import TrackingPlans

@Suite("CollectorBatchEncoder: errors")
struct CollectorEncodingErrorTests {
    @Event(name: "checkout_started", version: 2)
    struct CheckoutStarted {
        var cartSize: Int
    }

    @Event(name: "measured")
    struct Measured {
        var value: Double
    }

    @Event(name: "measured_once")
    struct MeasuredOnce {
        var value: Float
    }

    @Event(name: "scheduled")
    struct Scheduled {
        var at: Date
    }

    struct HandWritten: Event {
        var plan: String
    }

    /// Encodes as a bare integer rather than a map of its properties.
    struct NotAMap: Event, Encodable {
        static let name = "not_a_map"

        init() {}

        func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(1)
        }
    }

    @Test("An event the plan doesn't describe is left out for unknownEvent with its name and version")
    func unknownEvent() throws {
        let sut = CollectorBatchEncoder(plan: try TrackingPlan(schemas: []), instrument: NoOpInstrument())
        let record = EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)
        let expected = CollectorEncodingError.unknownEvent(name: "checkout_started", version: 2)

        let actual = sut.batch(of: [record]).skippedRecords.map(\.reason)

        #expect(actual == [expected])
    }

    @Test("An event whose version the plan doesn't describe is left out for unknownEvent, though the plan has its name")
    func unknownVersion() throws {
        let earlier = EventSchema(name: "checkout_started", version: 1, consentCategory: .analytics, properties: [])
        let sut = CollectorBatchEncoder(plan: try TrackingPlan(schemas: [earlier]), instrument: NoOpInstrument())
        let record = EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)
        let expected = CollectorEncodingError.unknownEvent(name: "checkout_started", version: 2)

        let actual = sut.batch(of: [record]).skippedRecords.map(\.reason)

        #expect(actual == [expected])
    }

    @Test("An event that isn't Encodable is left out for notEncodable")
    func notEncodable() throws {
        let schema = EventSchema(name: "HandWritten", version: 1, consentCategory: .analytics, properties: [EventSchema.Property(name: "plan", typeName: "String", isOptional: false)])
        let sut = CollectorBatchEncoder(plan: try TrackingPlan(schemas: [schema]), instrument: NoOpInstrument())
        let record = EventRecord(event: HandWritten(plan: "pro"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)
        let expected = CollectorEncodingError.notEncodable(name: "HandWritten")

        let actual = sut.batch(of: [record]).skippedRecords.map(\.reason)

        #expect(actual == [expected])
    }

    @Test("A NaN or infinite Double is left out for unrepresentableValue naming the property", arguments: [Double.nan, .infinity, -.infinity])
    func nonFiniteDouble(value: Double) throws {
        let sut = CollectorBatchEncoder(plan: try TrackingPlan(schemas: [Measured.schema]), instrument: NoOpInstrument())
        let record = EventRecord(event: Measured(value: value), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)
        let expected = CollectorEncodingError.unrepresentableValue(event: "measured", property: "value")

        let actual = sut.batch(of: [record]).skippedRecords.map(\.reason)

        #expect(actual == [expected])
    }

    @Test("A NaN or infinite Float is left out for unrepresentableValue naming the property", arguments: [Float.nan, .infinity])
    func nonFiniteFloat(value: Float) throws {
        let sut = CollectorBatchEncoder(plan: try TrackingPlan(schemas: [MeasuredOnce.schema]), instrument: NoOpInstrument())
        let record = EventRecord(event: MeasuredOnce(value: value), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)
        let expected = CollectorEncodingError.unrepresentableValue(event: "measured_once", property: "value")

        let actual = sut.batch(of: [record]).skippedRecords.map(\.reason)

        #expect(actual == [expected])
    }

    @Test("A Date of NaN or infinite seconds is left out for unrepresentableValue naming the property", arguments: [Double.nan, .infinity])
    func nonFiniteDate(seconds: Double) throws {
        let sut = CollectorBatchEncoder(plan: try TrackingPlan(schemas: [Scheduled.schema]), instrument: NoOpInstrument())
        let record = EventRecord(event: Scheduled(at: Date(timeIntervalSinceReferenceDate: seconds)), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)
        let expected = CollectorEncodingError.unrepresentableValue(event: "scheduled", property: "at")

        let actual = sut.batch(of: [record]).skippedRecords.map(\.reason)

        #expect(actual == [expected])
    }

    @Test("An event whose encoding isn't a map is left out for unrepresentableValue with no property")
    func notAMap() throws {
        let schema = EventSchema(name: "not_a_map", version: 1, consentCategory: .analytics, properties: [])
        let sut = CollectorBatchEncoder(plan: try TrackingPlan(schemas: [schema]), instrument: NoOpInstrument())
        let record = EventRecord(event: NotAMap(), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)
        let expected = CollectorEncodingError.unrepresentableValue(event: "not_a_map", property: "")

        let actual = sut.batch(of: [record]).skippedRecords.map(\.reason)

        #expect(actual == [expected])
    }
}
