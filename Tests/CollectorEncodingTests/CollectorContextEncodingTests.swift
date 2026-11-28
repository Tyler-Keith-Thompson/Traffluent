import CollectorEncoding
import EventMacros
import Foundation
import Instrumentation
import Sessions
import StandardContext
import Testing
import Trackers
import TrackingPlans

// Private: its events share their names with other events of this test target, and @Event
// leaves a private type's events out of the link check of names (DefiningEvents, Limits).
@Suite("CollectorBatchEncoder: context")
private struct CollectorContextEncodingTests {
    @Event(name: "opened")
    struct Opened {}

    enum ExperimentKey: ServiceContextKey {
        typealias Value = String
    }

    /// Injects the same keys and values into every carrier, whatever the context.
    struct FixedInstrument: Instrument {
        var values: [(key: String, value: String)]

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
            for (key, value) in values {
                injector.inject(value, forKey: key, into: &carrier)
            }
        }
    }

    @Test("A record tracked in the top-level context, with no instrument, has an empty context")
    func emptyContext() throws {
        let sut = CollectorBatchEncoder(plan: try TrackingPlan(schemas: [Opened.schema]), instrument: NoOpInstrument())
        let record = EventRecord(id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!, event: Opened(), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)
        let expected = #"{"records":[{"context":{},"id":"00000000-0000-4000-8000-000000000001","isRedelivered":false,"name":"opened","properties":{},"timestamp":"1970-01-01T00:00:00.000Z"}]}"#

        let actual = String(decoding: try #require(sut.batch(of: [record]).body).body, as: UTF8.self)

        #expect(actual == expected)
    }

    @Test("An application's nil values are left out of its object")
    func applicationWithoutValues() throws {
        let sut = CollectorBatchEncoder(plan: try TrackingPlan(schemas: [Opened.schema]), instrument: NoOpInstrument())
        var context = ServiceContext.topLevel
        context[ApplicationKey.self] = ApplicationKey.Value(bundleIdentifier: nil, version: "1.0", build: nil)
        let record = EventRecord(id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!, event: Opened(), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil, context: context)
        let expected = #"{"records":[{"context":{"application":{"version":"1.0"}},"id":"00000000-0000-4000-8000-000000000001","isRedelivered":false,"name":"opened","properties":{},"timestamp":"1970-01-01T00:00:00.000Z"}]}"#

        let actual = String(decoding: try #require(sut.batch(of: [record]).body).body, as: UTF8.self)

        #expect(actual == expected)
    }

    @Test(
        "Each form factor is written by its case's name",
        arguments: [
            (DeviceKey.Value.FormFactor.phone, "phone"), (.pad, "pad"), (.mac, "mac"), (.tv, "tv"), (.watch, "watch"), (.vision, "vision"),
        ]
    )
    func formFactors(formFactor: DeviceKey.Value.FormFactor, name: String) throws {
        let sut = CollectorBatchEncoder(plan: try TrackingPlan(schemas: [Opened.schema]), instrument: NoOpInstrument())
        var context = ServiceContext.topLevel
        context[DeviceKey.self] = DeviceKey.Value(model: "Model1,1", formFactor: formFactor)
        let record = EventRecord(id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!, event: Opened(), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil, context: context)
        let expected = #"{"records":[{"context":{"device":{"formFactor":""# + name + #"","model":"Model1,1"}},"id":"00000000-0000-4000-8000-000000000001","isRedelivered":false,"name":"opened","properties":{},"timestamp":"1970-01-01T00:00:00.000Z"}]}"#

        let actual = String(decoding: try #require(sut.batch(of: [record]).body).body, as: UTF8.self)

        #expect(actual == expected)
    }

    @Test(
        "Each network connection is written by its case's name",
        arguments: [
            (NetworkKey.Value.wifi, "wifi"), (.cellular, "cellular"), (.wiredEthernet, "wiredEthernet"), (.other, "other"), (.offline, "offline"),
        ]
    )
    func networks(network: NetworkKey.Value, name: String) throws {
        let sut = CollectorBatchEncoder(plan: try TrackingPlan(schemas: [Opened.schema]), instrument: NoOpInstrument())
        var context = ServiceContext.topLevel
        context[NetworkKey.self] = network
        let record = EventRecord(id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!, event: Opened(), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil, context: context)
        let expected = #"{"records":[{"context":{"network":""# + name + #""},"id":"00000000-0000-4000-8000-000000000001","isRedelivered":false,"name":"opened","properties":{},"timestamp":"1970-01-01T00:00:00.000Z"}]}"#

        let actual = String(decoding: try #require(sut.batch(of: [record]).body).body, as: UTF8.self)

        #expect(actual == expected)
    }

    @Test("A locale is its BCP 47 identifier")
    func locale() throws {
        let sut = CollectorBatchEncoder(plan: try TrackingPlan(schemas: [Opened.schema]), instrument: NoOpInstrument())
        var context = ServiceContext.topLevel
        context[LocaleKey.self] = Locale(identifier: "pt_BR")
        let record = EventRecord(id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!, event: Opened(), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil, context: context)
        let expected = #"{"records":[{"context":{"locale":"pt-BR"},"id":"00000000-0000-4000-8000-000000000001","isRedelivered":false,"name":"opened","properties":{},"timestamp":"1970-01-01T00:00:00.000Z"}]}"#

        let actual = String(decoding: try #require(sut.batch(of: [record]).body).body, as: UTF8.self)

        #expect(actual == expected)
    }

    @Test("Every field the instrument injects is in trace, and a key the encoder doesn't know is left out")
    func traceAndUnknownKeys() throws {
        let instrument = FixedInstrument(values: [(key: "traceparent", value: "00-a-b-01"), (key: "tracestate", value: "vendor=1")])
        let sut = CollectorBatchEncoder(plan: try TrackingPlan(schemas: [Opened.schema]), instrument: instrument)
        var context = ServiceContext.topLevel
        context[ExperimentKey.self] = "new-checkout"
        context[SampleRateKey.self] = try SampleRate(0.125)
        context[SessionKey.self] = UUID(uuidString: "00000000-0000-4000-8000-00000000000A")!
        let record = EventRecord(id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!, event: Opened(), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil, context: context)
        let expected = #"{"records":[{"context":{"sampleRate":0.125,"session":"00000000-0000-4000-8000-00000000000A","trace":{"traceparent":"00-a-b-01","tracestate":"vendor=1"}},"id":"00000000-0000-4000-8000-000000000001","isRedelivered":false,"name":"opened","properties":{},"timestamp":"1970-01-01T00:00:00.000Z"}]}"#

        let actual = String(decoding: try #require(sut.batch(of: [record]).body).body, as: UTF8.self)

        #expect(actual == expected)
    }

    @Test("Each record's own trace context is written, not only the first's")
    func eachRecordsTrace() throws {
        let sut = CollectorBatchEncoder(plan: try TrackingPlan(schemas: [Opened.schema]), instrument: FixedInstrument(values: []))
        var context = ServiceContext.topLevel
        context[SampleRateKey.self] = try SampleRate(1)
        let first = EventRecord(id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!, event: Opened(), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil, context: context)
        let second = EventRecord(id: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!, event: Opened(), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)
        let expected = #"{"records":[{"context":{"sampleRate":1},"id":"00000000-0000-4000-8000-000000000001","isRedelivered":false,"name":"opened","properties":{},"timestamp":"1970-01-01T00:00:00.000Z"},{"context":{},"id":"00000000-0000-4000-8000-000000000002","isRedelivered":false,"name":"opened","properties":{},"timestamp":"1970-01-01T00:00:00.000Z"}]}"#

        let actual = String(decoding: try #require(sut.batch(of: [first, second]).body).body, as: UTF8.self)

        #expect(actual == expected)
    }
}
