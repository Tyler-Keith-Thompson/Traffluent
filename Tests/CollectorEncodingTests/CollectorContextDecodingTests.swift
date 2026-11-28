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
@Suite("CollectorBatchDecoder: context")
private struct CollectorContextDecodingTests {
    @Event(name: "opened")
    struct Opened {}

    @Test(
        "A context member that doesn't hold what the encoder writes is reported by its path",
        arguments: [
            (#"{"application":"shop"}"#, "context.application"),
            (#"{"application":{"version":2}}"#, "context.application"),
            (#"{"application":{"bundleIdentifier":null}}"#, "context.application"),
            (#"{"application":{"build":["1"]}}"#, "context.application"),
            (#"{"device":{"model":"iPhone17,1"}}"#, "context.device"),
            (#"{"device":{"formFactor":"phone"}}"#, "context.device"),
            (#"{"device":{"formFactor":"laptop","model":"Mac"}}"#, "context.device"),
            (#"{"device":{"formFactor":"Phone","model":"iPhone17,1"}}"#, "context.device"),
            (#"{"device":"phone"}"#, "context.device"),
            (#"{"locale":5}"#, "context.locale"),
            (#"{"network":"ethernet"}"#, "context.network"),
            (#"{"network":true}"#, "context.network"),
            (#"{"operatingSystem":{"name":"iOS"}}"#, "context.operatingSystem"),
            (#"{"operatingSystem":{"version":"26.1"}}"#, "context.operatingSystem"),
            (#"{"operatingSystem":"iOS"}"#, "context.operatingSystem"),
            (#"{"sampleRate":1.5}"#, "context.sampleRate"),
            (#"{"sampleRate":-0.5}"#, "context.sampleRate"),
            (#"{"sampleRate":"0.5"}"#, "context.sampleRate"),
            (#"{"session":"00000000-0000-4000-8000-00000000000"}"#, "context.session"),
            (#"{"session":5}"#, "context.session"),
            (#"{"session":null}"#, "context.session"),
            (#"{"trace":"00-4bf9"}"#, "context.trace"),
            (#"{"trace":{"traceparent":5}}"#, "context.trace"),
            (#"{"vendorIdentifier":"vendor"}"#, "context.vendorIdentifier"),
            (#"{"vendorIdentifier":null}"#, "context.vendorIdentifier"),
        ]
    )
    func malformedContext(context: String, member: String) throws {
        let sut = try CollectorBatchDecoder(plan: try TrackingPlan(schemas: [Opened.schema]), events: [Opened.self], instrument: NoOpInstrument())
        let body = Data((#"{"records":[{"context":"# + context + #","id":"00000000-0000-4000-8000-000000000001","isRedelivered":false,"name":"opened","properties":{},"timestamp":"1970-01-01T00:00:00.000Z","version":1}]}"#).utf8)
        let expected = [UndecodedRecord(offset: 0, recordID: UUID(uuidString: "00000000-0000-4000-8000-000000000001"), eventName: "opened", reason: .malformedMember(member))]

        let actual = try sut.batch(from: body)

        #expect(actual.undecodedRecords == expected)
        #expect(actual.records.isEmpty)
    }

    @Test(
        "Each context value at the edge of what the encoder writes reads back, and encodes again to the same bytes",
        arguments: [
            #"{}"#,
            #"{"application":{}}"#,
            #"{"application":{"bundleIdentifier":"com.example.shop"}}"#,
            #"{"application":{"build":"1"}}"#,
            #"{"device":{"formFactor":"pad","model":"iPad16,3"}}"#,
            #"{"device":{"formFactor":"mac","model":"Mac16,1"}}"#,
            #"{"device":{"formFactor":"tv","model":"AppleTV14,1"}}"#,
            #"{"device":{"formFactor":"watch","model":"Watch7,1"}}"#,
            #"{"device":{"formFactor":"vision","model":"RealityDevice14,1"}}"#,
            #"{"locale":"fr-CA"}"#,
            #"{"network":"cellular"}"#,
            #"{"network":"wiredEthernet"}"#,
            #"{"network":"other"}"#,
            #"{"network":"offline"}"#,
            #"{"network":"wifi"}"#,
            #"{"operatingSystem":{"name":"Linux","version":"6.8.0"}}"#,
            #"{"sampleRate":0}"#,
            #"{"sampleRate":1}"#,
            #"{"sampleRate":0.001}"#,
            #"{"session":"00000000-0000-7000-8000-00000000000A"}"#,
        ]
    )
    func contextRoundTrip(context: String) throws {
        let plan = try TrackingPlan(schemas: [Opened.schema])
        let sut = try CollectorBatchDecoder(plan: plan, events: [Opened.self], instrument: NoOpInstrument())
        let encoder = CollectorBatchEncoder(plan: plan, instrument: NoOpInstrument())
        let expected = Data((#"{"records":[{"context":"# + context + #","id":"00000000-0000-4000-8000-000000000001","isRedelivered":false,"name":"opened","properties":{},"timestamp":"1970-01-01T00:00:00.000Z","version":1}]}"#).utf8)

        let decoded = try sut.batch(from: expected)
        let actual = encoder.batch(of: decoded.records).body?.body

        #expect(decoded.undecodedRecords.isEmpty)
        #expect(actual == expected)
    }

    @Test("A context member the encoder doesn't write is left out, and the record decodes")
    func unknownContextMember() throws {
        let sut = try CollectorBatchDecoder(plan: try TrackingPlan(schemas: [Opened.schema]), events: [Opened.self], instrument: NoOpInstrument())
        let body = Data(#"{"records":[{"context":{"experiment":"b","session":"00000000-0000-4000-8000-00000000000A"},"id":"00000000-0000-4000-8000-000000000001","isRedelivered":false,"name":"opened","properties":{},"timestamp":"1970-01-01T00:00:00.000Z","version":1}]}"#.utf8)
        let expected = UUID(uuidString: "00000000-0000-4000-8000-00000000000A")

        let actual = try sut.batch(from: body)

        #expect(actual.undecodedRecords.isEmpty)
        #expect(actual.records.first?.context[SessionKey.self] == expected)
    }

    /// Records every carrier it is asked to extract from, and extracts nothing.
    final class RecordingInstrument: Instrument, @unchecked Sendable {
        // Read only after the decoder returns, on the test's own task.
        var carriers: [[String: String]] = []

        func extract<Carrier, Extract: Extractor>(
            _ carrier: Carrier,
            into context: inout ServiceContext,
            using extractor: Extract
        ) where Extract.Carrier == Carrier {
            if let fields = carrier as? [String: String] {
                carriers.append(fields)
            }
        }

        func inject<Carrier, Inject: Injector>(
            _ context: ServiceContext,
            into carrier: inout Carrier,
            using injector: Inject
        ) where Inject.Carrier == Carrier {}
    }

    @Test("The trace member's fields are handed to the instrument, and a record without one hands it nothing")
    func traceExtracted() throws {
        let instrument = RecordingInstrument()
        let sut = try CollectorBatchDecoder(plan: try TrackingPlan(schemas: [Opened.schema]), events: [Opened.self], instrument: instrument)
        let body = Data(#"{"records":[{"context":{"trace":{"traceparent":"00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01","tracestate":"a=1"}},"id":"00000000-0000-4000-8000-000000000001","isRedelivered":false,"name":"opened","properties":{},"timestamp":"1970-01-01T00:00:00.000Z","version":1},{"context":{},"id":"00000000-0000-4000-8000-000000000002","isRedelivered":false,"name":"opened","properties":{},"timestamp":"1970-01-01T00:00:00.000Z","version":1}]}"#.utf8)
        let expected = [["traceparent": "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01", "tracestate": "a=1"]]

        _ = try sut.batch(from: body)

        #expect(instrument.carriers == expected)
    }
}
