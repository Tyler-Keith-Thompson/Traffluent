import CollectorEncoding
import EventMacros
import Foundation
import Instrumentation
import Testing
import TrackingPlans

@Suite("CollectorBatchDecoder: timestamps")
struct CollectorTimestampDecodingTests {
    @Event(name: "dates")
    struct Dated {
        var at: Date
    }

    @Test(
        "A timestamp of the encoder's form, at the edges of each field, reads back and encodes again to itself",
        arguments: [
            "1970-01-01T00:00:00.000Z",
            "1969-12-31T23:59:59.999Z",
            "2026-11-23T14:03:27.512Z",
            "2024-02-29T00:00:00.000Z",
            "2000-02-29T12:00:00.000Z",
            "2023-02-28T23:59:59.999Z",
            "2026-01-31T00:00:00.000Z",
            "2026-04-30T00:00:00.000Z",
            "2026-12-31T23:59:59.999Z",
            // Found by FuzzCollectorEncoding: the Double nearest its start is many steps of a Date's
            // seconds since 2001 below the first that rounds down into it.
            "2004-03-08T22:30:07.616Z",
            "2001-01-01T00:00:00.001Z",
            "2000-12-31T23:59:59.999Z",
            "0001-01-01T00:00:00.000Z",
            "0000-01-01T00:00:00.000Z",
            "-0001-12-31T23:59:59.999Z",
            "-0400-02-29T00:00:00.000Z",
            "9999-12-31T23:59:59.999Z",
            "10000-01-01T00:00:00.000Z",
            "275760-09-13T00:00:00.000Z",
            "-271821-04-20T00:00:00.000Z",
        ]
    )
    func readsBack(timestamp: String) throws {
        let plan = try TrackingPlan(schemas: [Dated.schema])
        let sut = try CollectorBatchDecoder(plan: plan, events: [Dated.self], instrument: NoOpInstrument())
        let encoder = CollectorBatchEncoder(plan: plan, instrument: NoOpInstrument())
        let expected = Data((#"{"records":[{"context":{},"id":"00000000-0000-4000-8000-000000000001","isRedelivered":false,"name":"dates","properties":{"at":""# + timestamp + #""},"timestamp":""# + timestamp + #""}]}"#).utf8)

        let decoded = try sut.batch(from: expected)
        let actual = encoder.batch(of: decoded.records).body?.body

        #expect(decoded.undecodedRecords.isEmpty)
        #expect(actual == expected)
    }

    @Test("A timestamp reads back as the start of its millisecond")
    func startOfMillisecond() throws {
        let sut = try CollectorBatchDecoder(plan: try TrackingPlan(schemas: [Dated.schema]), events: [Dated.self], instrument: NoOpInstrument())
        let body = Data(#"{"records":[{"context":{},"id":"00000000-0000-4000-8000-000000000001","isRedelivered":false,"name":"dates","properties":{"at":"2001-01-01T00:00:00.250Z"},"timestamp":"1970-01-01T00:00:01.500Z"}]}"#.utf8)
        let expectedTimestamp = Date(timeIntervalSince1970: 1.5)
        let expectedAt = Date(timeIntervalSinceReferenceDate: 0.25)

        let record = try #require(try sut.batch(from: body).records.first)

        #expect(record.timestamp == expectedTimestamp)
        #expect((record.event as? Dated)?.at == expectedAt)
    }

    @Test(
        "A timestamp of any other form, or of a day or time that doesn't exist, is a malformed timestamp",
        arguments: [
            "1970-00-01T00:00:00.000Z",
            "1970-13-01T00:00:00.000Z",
            "1970-01-00T00:00:00.000Z",
            "1970-01-32T00:00:00.000Z",
            "2023-02-29T00:00:00.000Z",
            "1900-02-29T00:00:00.000Z",
            "2026-04-31T00:00:00.000Z",
            "2026-06-31T00:00:00.000Z",
            "2026-09-31T00:00:00.000Z",
            "2026-11-31T00:00:00.000Z",
            "1970-01-01T24:00:00.000Z",
            "1970-01-01T00:60:00.000Z",
            "1970-01-01T00:00:60.000Z",
            "1970-01-01T00:00:00.000z",
            "1970-01-01t00:00:00.000Z",
            "1970-01-01T00:00:00.000",
            "1970-01-01T00:00:00Z",
            "1970-01-01T00:00:00.0000Z",
            "1970-01-01T00:00:00.000ZZ",
            "1970-01-01T00:00:00.000+00:00",
            "1970-01-01 00:00:00.000Z",
            "1970/01/01T00:00:00.000Z",
            "1970-01-01T00.00.00.000Z",
            "1970-01-01T00:00:00,000Z",
            "970-01-01T00:00:00.000Z",
            "01970-01-01T00:00:00.000Z",
            "-0000-01-01T00:00:00.000Z",
            "+1970-01-01T00:00:00.000Z",
            "1970-1-01T00:00:00.000Z",
            "1970-01-01T0a:00:00.000Z",
            "1970-0a-01T00:00:00.000Z",
            "1970-01-01T00:00:00.00aZ",
            "292278995-01-01T00:00:00.000Z",
            "-292275056-01-01T00:00:00.000Z",
            "1000000000000-01-01T00:00:00.000Z",
            "",
            "-",
        ]
    )
    func malformed(timestamp: String) throws {
        let sut = try CollectorBatchDecoder(plan: try TrackingPlan(schemas: [Dated.schema]), events: [Dated.self], instrument: NoOpInstrument())
        let body = Data((#"{"records":[{"context":{},"id":"00000000-0000-4000-8000-000000000001","isRedelivered":false,"name":"dates","properties":{"at":"1970-01-01T00:00:00.000Z"},"timestamp":""# + timestamp + #""},{"context":{},"id":"00000000-0000-4000-8000-000000000002","isRedelivered":false,"name":"dates","properties":{"at":""# + timestamp + #""},"timestamp":"1970-01-01T00:00:00.000Z"}]}"#).utf8)
        let expected = [
            UndecodedRecord(offset: 0, recordID: UUID(uuidString: "00000000-0000-4000-8000-000000000001"), eventName: "dates", reason: .malformedMember("timestamp")),
            UndecodedRecord(offset: 1, recordID: UUID(uuidString: "00000000-0000-4000-8000-000000000002"), eventName: "dates", reason: .undecodableProperty(event: "dates", property: "at")),
        ]

        let actual = try sut.batch(from: body)

        #expect(actual.undecodedRecords == expected)
    }

    @Test("Dates near both ends of the millisecond counts Int64 holds read back, and encode again to themselves")
    func int64Extremes() throws {
        let plan = try TrackingPlan(schemas: [Dated.schema])
        let sut = try CollectorBatchDecoder(plan: plan, events: [Dated.self], instrument: NoOpInstrument())
        let encoder = CollectorBatchEncoder(plan: plan, instrument: NoOpInstrument())
        // The Dates nearest Int64.min and Int64.max milliseconds whose timestamps exist, written by the
        // encoder, which writes only a date a Double holds.
        let dates = [Date(timeIntervalSince1970: -9_223_372_036_854_000), Date(timeIntervalSince1970: 9_223_372_036_854_000)]
        let records = dates.enumerated().map { offset, date in
            EventRecord(id: UUID(uuidString: "00000000-0000-4000-8000-00000000000\(offset)")!, event: Dated(at: date), timestamp: date, sourceLocation: nil)
        }
        let encoded = encoder.batch(of: records)
        let expected = try #require(encoded.body?.body)

        let decoded = try sut.batch(from: expected)
        let actual = encoder.batch(of: decoded.records).body?.body

        #expect(encoded.skippedRecords.isEmpty)
        #expect(decoded.undecodedRecords.isEmpty)
        #expect(actual == expected)
    }
}
