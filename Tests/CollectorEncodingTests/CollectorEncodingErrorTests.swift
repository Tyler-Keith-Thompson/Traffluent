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
    struct NotAMap: Event, BinaryCodable {
        static let name = "not_a_map"

        init() {}

        func encode(to encoder: inout BinaryEncoder) {
            encoder.encode(1)
        }

        init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {}
    }

    @Test("An event the plan doesn't describe throws unknownEvent with its name and version")
    func unknownEvent() {
        let sut = CollectorBatchEncoder(plan: TrackingPlan(schemas: []), instrument: NoOpInstrument())
        let record = EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)
        let expected = CollectorEncodingError.unknownEvent(name: "checkout_started", version: 2)

        #expect(throws: expected) {
            try sut.encode([record])
        }
    }

    @Test("An event whose version the plan doesn't describe throws unknownEvent, though the plan has its name")
    func unknownVersion() {
        let earlier = EventSchema(name: "checkout_started", version: 1, consentCategory: .analytics, properties: [])
        let sut = CollectorBatchEncoder(plan: TrackingPlan(schemas: [earlier]), instrument: NoOpInstrument())
        let record = EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)
        let expected = CollectorEncodingError.unknownEvent(name: "checkout_started", version: 2)

        #expect(throws: expected) {
            try sut.encode([record])
        }
    }

    @Test("An event that isn't BinaryCodable throws notBinaryCodable")
    func notBinaryCodable() {
        let schema = EventSchema(name: "HandWritten", version: 1, consentCategory: .analytics, properties: [EventSchema.Property(name: "plan", typeName: "String", isOptional: false)])
        let sut = CollectorBatchEncoder(plan: TrackingPlan(schemas: [schema]), instrument: NoOpInstrument())
        let record = EventRecord(event: HandWritten(plan: "pro"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)
        let expected = CollectorEncodingError.notBinaryCodable(name: "HandWritten")

        #expect(throws: expected) {
            try sut.encode([record])
        }
    }

    @Test("A NaN or infinite Double throws unrepresentableValue naming the property", arguments: [Double.nan, .infinity, -.infinity])
    func nonFiniteDouble(value: Double) {
        let sut = CollectorBatchEncoder(plan: TrackingPlan(schemas: [Measured.schema]), instrument: NoOpInstrument())
        let record = EventRecord(event: Measured(value: value), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)
        let expected = CollectorEncodingError.unrepresentableValue(event: "measured", property: "value")

        #expect(throws: expected) {
            try sut.encode([record])
        }
    }

    @Test("A NaN or infinite Float throws unrepresentableValue naming the property", arguments: [Float.nan, .infinity])
    func nonFiniteFloat(value: Float) {
        let sut = CollectorBatchEncoder(plan: TrackingPlan(schemas: [MeasuredOnce.schema]), instrument: NoOpInstrument())
        let record = EventRecord(event: MeasuredOnce(value: value), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)
        let expected = CollectorEncodingError.unrepresentableValue(event: "measured_once", property: "value")

        #expect(throws: expected) {
            try sut.encode([record])
        }
    }

    @Test("A Date of NaN or infinite seconds throws unrepresentableValue naming the property", arguments: [Double.nan, .infinity])
    func nonFiniteDate(seconds: Double) {
        let sut = CollectorBatchEncoder(plan: TrackingPlan(schemas: [Scheduled.schema]), instrument: NoOpInstrument())
        let record = EventRecord(event: Scheduled(at: Date(timeIntervalSinceReferenceDate: seconds)), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)
        let expected = CollectorEncodingError.unrepresentableValue(event: "scheduled", property: "at")

        #expect(throws: expected) {
            try sut.encode([record])
        }
    }

    @Test("An event whose encoding isn't a map throws unrepresentableValue with no property")
    func notAMap() {
        let schema = EventSchema(name: "not_a_map", version: 1, consentCategory: .analytics, properties: [])
        let sut = CollectorBatchEncoder(plan: TrackingPlan(schemas: [schema]), instrument: NoOpInstrument())
        let record = EventRecord(event: NotAMap(), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)
        let expected = CollectorEncodingError.unrepresentableValue(event: "not_a_map", property: "")

        #expect(throws: expected) {
            try sut.encode([record])
        }
    }
}
