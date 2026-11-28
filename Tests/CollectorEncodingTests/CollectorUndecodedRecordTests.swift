import CollectorEncoding
import EventMacros
import Foundation
import Instrumentation
import Testing
import TrackingPlans

// Private: its events share their names with other events of this test target, and @Event
// leaves a private type's events out of the link check of names (DefiningEvents, Limits).
@Suite("CollectorBatchDecoder: records it can't read")
private struct CollectorUndecodedRecordTests {
    @Event(name: "paid")
    struct Paid {
        var amount: Int
        var card: Sensitive<String>
        var note: Sensitive<String>?
        var code: Refined<String, NonEmpty>
    }

    @Event(name: "opened", version: 2)
    struct Opened {}

    enum NonEmpty: Refinement {
        static var constraints: [Constraint<String>] {
            get throws(InvalidConstraint) { try [.minLength(1)] }
        }
    }

    @Event(name: "opened")
    struct OpenedAtVersionOne {}

    static let good = #"{"context":{},"id":"00000000-0000-4000-8000-000000000001","isRedelivered":false,"name":"paid","properties":{"amount":5,"card":"4242","code":"A","note":null},"timestamp":"1970-01-01T00:00:00.000Z"}"#
    static let later = #"{"context":{},"id":"00000000-0000-4000-8000-000000000003","isRedelivered":false,"name":"paid","properties":{"amount":6,"card":"4242","code":"B","note":null},"timestamp":"1970-01-01T00:00:00.000Z"}"#

    @Test(
        "A record the decoder can't read is reported with its offset, id, name and reason, and the records around it decode",
        arguments: [
            (#"{"context":{},"id":"00000000-0000-4000-8000-000000000002","isRedelivered":false,"name":"refunded","properties":{},"timestamp":"1970-01-01T00:00:00.000Z"}"#, "refunded", CollectorDecodingError.unknownEvent(name: "refunded")),
            (#"{"context":{},"id":"00000000-0000-4000-8000-000000000002","isRedelivered":false,"name":"opened","properties":{},"timestamp":"1970-01-01T00:00:00.000Z","version":2}"#, "opened", .unknownVersion(name: "opened", version: 2)),
            (#"{"context":{},"id":"00000000-0000-4000-8000-000000000002","isRedelivered":false,"name":"opened","properties":{},"timestamp":"1970-01-01T00:00:00.000Z"}"#, "opened", .unknownVersion(name: "opened", version: 1)),
            (#"{"context":{},"id":"00000000-0000-4000-8000-000000000002","isRedelivered":false,"name":"paid","properties":{"amount":5,"card":"4242","code":"A"},"timestamp":"1970-01-01T00:00:00.000Z","version":null}"#, "paid", .malformedMember("version")),
            (#"{"context":{},"id":"00000000-0000-4000-8000-000000000002","isRedelivered":false,"name":"paid","properties":{"amount":"5","card":"4242","code":"A"},"timestamp":"1970-01-01T00:00:00.000Z"}"#, "paid", .undecodableProperty(event: "paid", property: "amount")),
            (#"{"context":{},"id":"00000000-0000-4000-8000-000000000002","isRedelivered":false,"name":"paid","properties":{"amount":5,"code":"A"},"timestamp":"1970-01-01T00:00:00.000Z"}"#, "paid", .undecodableProperty(event: "paid", property: "card")),
            (#"{"context":{},"id":"00000000-0000-4000-8000-000000000002","isRedelivered":false,"name":"paid","properties":{"amount":5,"card":"4242","code":""},"timestamp":"1970-01-01T00:00:00.000Z"}"#, "paid", .undecodableProperty(event: "paid", property: "code")),
            (#"{"context":{},"id":"00000000-0000-4000-8000-000000000002","isRedelivered":false,"name":"paid","properties":{"amount":5.5,"card":"4242","code":"A"},"timestamp":"1970-01-01T00:00:00.000Z"}"#, "paid", .undecodableProperty(event: "paid", property: "amount")),
            (#"{"context":{"session":"not a uuid"},"id":"00000000-0000-4000-8000-000000000002","isRedelivered":false,"name":"paid","properties":{"amount":5,"card":"4242","code":"A"},"timestamp":"1970-01-01T00:00:00.000Z"}"#, "paid", .malformedMember("context.session")),
            (#"{"context":{},"id":"00000000-0000-4000-8000-000000000002","isRedelivered":false,"name":"paid","properties":{"amount":5,"card":"4242","code":"A"},"timestamp":"1970-01-01T00:00:00Z"}"#, "paid", .malformedMember("timestamp")),
            (#"{"context":{},"id":"00000000-0000-4000-8000-000000000002","isRedelivered":false,"name":"paid","properties":[],"timestamp":"1970-01-01T00:00:00.000Z"}"#, "paid", .malformedMember("properties")),
            (#"{"context":[],"id":"00000000-0000-4000-8000-000000000002","isRedelivered":false,"name":"paid","properties":{},"timestamp":"1970-01-01T00:00:00.000Z"}"#, "paid", .malformedMember("context")),
            (#"{"context":{},"id":"00000000-0000-4000-8000-000000000002","isRedelivered":"false","name":"paid","properties":{},"timestamp":"1970-01-01T00:00:00.000Z"}"#, "paid", .malformedMember("isRedelivered")),
            (#"{"context":{},"id":"00000000-0000-4000-8000-000000000002","name":"paid","properties":{},"timestamp":"1970-01-01T00:00:00.000Z"}"#, "paid", .malformedMember("isRedelivered")),
            (#"{"context":{},"id":"00000000-0000-4000-8000-000000000002","isRedelivered":false,"name":5,"properties":{},"timestamp":"1970-01-01T00:00:00.000Z"}"#, nil, .malformedMember("name")),
            (#"{"context":{},"id":"00000000-0000-4000-8000-000000000002","isRedelivered":false,"properties":{},"timestamp":"1970-01-01T00:00:00.000Z"}"#, nil, .malformedMember("name")),
            (#"{"context":{},"id":"00000000-0000-4000-8000-000000000002","isRedelivered":false,"name":"paid","properties":{},"timestamp":5}"#, "paid", .malformedMember("timestamp")),
            (#"{"context":{},"id":"00000000-0000-4000-8000-000000000002","isRedelivered":false,"name":"paid","properties":{}}"#, "paid", .malformedMember("timestamp")),
        ] as [(String, String?, CollectorDecodingError)]
    )
    func undecodedRecord(record: String, name: String?, reason: CollectorDecodingError) throws {
        let plan = try TrackingPlan(schemas: [Paid.schema, OpenedAtVersionOne.schema])
        let sut = try CollectorBatchDecoder(plan: plan, events: [Paid.self, Opened.self], instrument: NoOpInstrument())
        let body = Data((#"{"records":["# + Self.good + "," + record + "," + Self.later + "]}").utf8)
        let expected = [UndecodedRecord(offset: 1, recordID: UUID(uuidString: "00000000-0000-4000-8000-000000000002"), eventName: name, reason: reason)]
        let expectedIDs = [UUID(uuidString: "00000000-0000-4000-8000-000000000001"), UUID(uuidString: "00000000-0000-4000-8000-000000000003")]

        let actual = try sut.batch(from: body)

        #expect(actual.undecodedRecords == expected)
        #expect(actual.records.map(\.id) == expectedIDs.compactMap { $0 })
    }

    @Test(
        "A record without an id that is a UUID string is reported without one",
        arguments: [
            #"{"context":{},"id":"not a uuid","isRedelivered":false,"name":"paid","properties":{},"timestamp":"1970-01-01T00:00:00.000Z"}"#,
            #"{"context":{},"id":5,"isRedelivered":false,"name":"paid","properties":{},"timestamp":"1970-01-01T00:00:00.000Z"}"#,
            #"{"context":{},"isRedelivered":false,"name":"paid","properties":{},"timestamp":"1970-01-01T00:00:00.000Z"}"#,
        ]
    )
    func missingID(record: String) throws {
        let plan = try TrackingPlan(schemas: [Paid.schema])
        let sut = try CollectorBatchDecoder(plan: plan, events: [Paid.self], instrument: NoOpInstrument())
        let body = Data((#"{"records":["# + record + "]}").utf8)
        let expected = [UndecodedRecord(offset: 0, recordID: nil, eventName: "paid", reason: .malformedMember("id"))]

        let actual = try sut.batch(from: body)

        #expect(actual.undecodedRecords == expected)
        #expect(actual.records.isEmpty)
    }

    @Test("A record that isn't an object is reported as notAnObject, without an id or a name", arguments: ["null", "5", #""paid""#, "[]"])
    func recordNotAnObject(record: String) throws {
        let plan = try TrackingPlan(schemas: [Paid.schema])
        let sut = try CollectorBatchDecoder(plan: plan, events: [Paid.self], instrument: NoOpInstrument())
        let body = Data((#"{"records":["# + Self.good + "," + record + "]}").utf8)
        let expected = [UndecodedRecord(offset: 1, recordID: nil, eventName: nil, reason: .notAnObject)]

        let actual = try sut.batch(from: body)

        #expect(actual.undecodedRecords == expected)
        #expect(actual.records.count == 1)
    }

    @Test("A redacted optional Sensitive property reads back as nil, and a present one as its value")
    func redactedOptionalSensitive() throws {
        let plan = try TrackingPlan(schemas: [Paid.schema])
        let sut = try CollectorBatchDecoder(plan: plan, events: [Paid.self], instrument: NoOpInstrument())
        let body = Data(#"{"records":[{"context":{},"id":"00000000-0000-4000-8000-000000000001","isRedelivered":false,"name":"paid","properties":{"amount":5,"card":"4242","code":"A"},"timestamp":"1970-01-01T00:00:00.000Z"},{"context":{},"id":"00000000-0000-4000-8000-000000000002","isRedelivered":false,"name":"paid","properties":{"amount":5,"card":"4242","code":"A","note":"gift"},"timestamp":"1970-01-01T00:00:00.000Z"}]}"#.utf8)
        let expectedNote = "gift"

        let actual = try sut.batch(from: body)
        let events = actual.records.compactMap { $0.event as? Paid }

        try #require(events.count == 2)
        #expect(events[0].note == nil)
        #expect(events[1].note?.value == expectedNote)
    }

    @Event(name: "counted")
    struct Counted {
        var small: UInt8
        var unsigned: UInt
        var signed: Int8
        var medium: Int32
        var tags: [Sensitive<String>]
    }

    @Test(
        "An integer outside its property's type, or a redacted element of a non-optional array, is an undecodable property naming it",
        arguments: [
            (#""small":300,"unsigned":0,"signed":0,"medium":0,"tags":[]"#, "small"),
            (#""small":256,"unsigned":0,"signed":0,"medium":0,"tags":[]"#, "small"),
            (#""small":-1,"unsigned":0,"signed":0,"medium":0,"tags":[]"#, "small"),
            (#""small":0,"unsigned":-1,"signed":0,"medium":0,"tags":[]"#, "unsigned"),
            (#""small":0,"unsigned":0,"signed":128,"medium":0,"tags":[]"#, "signed"),
            (#""small":0,"unsigned":0,"signed":-129,"medium":0,"tags":[]"#, "signed"),
            (#""small":0,"unsigned":0,"signed":0,"medium":2147483648,"tags":[]"#, "medium"),
            (#""small":0,"unsigned":0,"signed":0,"medium":-2147483649,"tags":[]"#, "medium"),
            (#""small":0,"unsigned":0,"signed":0,"medium":0,"tags":["a",null]"#, "tags"),
        ]
    )
    func outOfRange(properties: String, property: String) throws {
        let plan = try TrackingPlan(schemas: [Counted.schema])
        let sut = try CollectorBatchDecoder(plan: plan, events: [Counted.self], instrument: NoOpInstrument())
        let body = Data((#"{"records":[{"context":{},"id":"00000000-0000-4000-8000-000000000001","isRedelivered":false,"name":"counted","properties":{"# + properties + #"},"timestamp":"1970-01-01T00:00:00.000Z"}]}"#).utf8)
        let expected = [UndecodedRecord(offset: 0, recordID: UUID(uuidString: "00000000-0000-4000-8000-000000000001"), eventName: "counted", reason: .undecodableProperty(event: "counted", property: property))]

        let actual = try sut.batch(from: body)

        #expect(actual.undecodedRecords == expected)
        #expect(actual.records.isEmpty)
    }

    @Test("The last integer each property's type holds reads back as itself")
    func inRange() throws {
        let plan = try TrackingPlan(schemas: [Counted.schema])
        let sut = try CollectorBatchDecoder(plan: plan, events: [Counted.self], instrument: NoOpInstrument())
        let body = Data(#"{"records":[{"context":{},"id":"00000000-0000-4000-8000-000000000001","isRedelivered":false,"name":"counted","properties":{"medium":-2147483648,"signed":127,"small":255,"tags":["a"],"unsigned":9223372036854775807},"timestamp":"1970-01-01T00:00:00.000Z"}]}"#.utf8)

        let event = try #require(try sut.batch(from: body).records.first?.event as? Counted)

        #expect(event.small == 255)
        #expect(event.signed == 127)
        #expect(event.medium == Int32.min)
        #expect(event.unsigned == UInt(Int64.max))
        #expect(event.tags.map(\.value) == ["a"])
    }
}
