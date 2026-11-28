import CollectorEncoding
import EventMacros
import Foundation
import Instrumentation
import Testing
import TrackingPlans

// Private: its events share their names with other events of this test target, and @Event
// leaves a private type's events out of the link check of names (DefiningEvents, Limits).
@Suite("CollectorBatchDecoder: bodies that aren't collector batches")
private struct NotACollectorBatchTests {
    @Event(name: "quoted")
    struct Quoted {}

    @Test(
        "A body that isn't a collector batch throws the reason",
        arguments: [
            ("", NotACollectorBatch.notJSON),
            ("{", .notJSON),
            (#"{"records":[]"#, .notJSON),
            ("records", .notJSON),
            (#"{"records":[1e400]}"#, .notJSON),
            ("null", .notAnObject),
            ("[]", .notAnObject),
            (#"[{"records":[]}]"#, .notAnObject),
            (#""records""#, .notAnObject),
            ("{}", .missingRecords),
            (#"{"record":[]}"#, .missingRecords),
            (#"{"records":null}"#, .recordsNotAnArray),
            (#"{"records":{}}"#, .recordsNotAnArray),
            (#"{"records":"[]"}"#, .recordsNotAnArray),
        ] as [(String, NotACollectorBatch)]
    )
    func notABatch(body: String, expected: NotACollectorBatch) throws {
        let sut = try CollectorBatchDecoder(plan: try TrackingPlan(schemas: [Quoted.schema]), events: [Quoted.self], instrument: NoOpInstrument())

        #expect(throws: expected) {
            try sut.batch(from: Data(body.utf8))
        }
    }

    @Test(
        "The smallest bodies that are batches decode without throwing: no records, and members beside records",
        arguments: [#"{"records":[]}"#, #" { "records" : [ ] } "#, #"{"records":[],"sentAt":"1970-01-01T00:00:00.000Z"}"#]
    )
    func emptyBatch(body: String) throws {
        let sut = try CollectorBatchDecoder(plan: try TrackingPlan(schemas: [Quoted.schema]), events: [Quoted.self], instrument: NoOpInstrument())

        let actual = try sut.batch(from: Data(body.utf8))

        #expect(actual.records.isEmpty)
        #expect(actual.undecodedRecords.isEmpty)
    }

    @Test("A batch whose every record is unreadable doesn't throw: each is reported")
    func everyRecordUnreadable() throws {
        let sut = try CollectorBatchDecoder(plan: try TrackingPlan(schemas: [Quoted.schema]), events: [Quoted.self], instrument: NoOpInstrument())
        let expected = [
            UndecodedRecord(offset: 0, recordID: nil, eventName: nil, reason: .notAnObject),
            UndecodedRecord(offset: 1, recordID: nil, eventName: nil, reason: .notAnObject),
        ]

        let actual = try sut.batch(from: Data(#"{"records":[1,2]}"#.utf8))

        #expect(actual.records.isEmpty)
        #expect(actual.undecodedRecords == expected)
    }
}
