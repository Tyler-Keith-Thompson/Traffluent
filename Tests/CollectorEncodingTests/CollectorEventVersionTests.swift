import CollectorEncoding
import EventMacros
import Foundation
import Instrumentation
import Testing
import TrackingPlans

// Private: its events share their names with each other, at different versions, and with other
// events of this test target, and @Event leaves a private type's events out of the link check of
// names (DefiningEvents, Limits). The earlier versions sit in a private enum of their own too, as a
// relay that links the app's current events beside them declares them.
@Suite("CollectorBatchEncoder and CollectorBatchDecoder: each record's event version")
private struct CollectorEventVersionTests {
    @Event(name: "rated", version: 2)
    struct Rated: Equatable {
        var stars: Int
        var comment: String
    }

    @Event(name: "rated", version: 3)
    struct RatedAtVersionThree: Equatable {
        var score: Double
    }

    // By hand: @Event takes only a positive version, and a hand-written event may declare any.
    struct RatedAtVersionZero: Event, Codable, Equatable {
        static let name = "rated"
        static let schemaVersion = 0
        static let schema = EventSchema(name: "rated", version: 0, consentCategory: .analytics, properties: [.init(name: "stars", typeName: "Int", isOptional: false)])

        var stars: Int
    }

    struct RatedAtVersionMinusOne: Event, Codable, Equatable {
        static let name = "rated"
        static let schemaVersion = -1
        static let schema = EventSchema(name: "rated", version: -1, consentCategory: .analytics, properties: [.init(name: "stars", typeName: "Int", isOptional: false)])

        var stars: Int
    }

    // Fileprivate, not private: @Event's expansion reaches the type from outside the suite, which
    // a private member type of it hides. A relay declares it at file scope, where private is the
    // same as fileprivate.
    fileprivate enum EarlierVersions {
        @Event(name: "rated")
        struct Rated: Equatable {
            var stars: Int
        }
    }

    static let v1 = #"{"context":{},"id":"00000000-0000-4000-8000-000000000001","isRedelivered":false,"name":"rated","properties":{"stars":4},"timestamp":"1970-01-01T00:00:00.000Z","version":1}"#
    static let v2 = #"{"context":{},"id":"00000000-0000-4000-8000-000000000003","isRedelivered":false,"name":"rated","properties":{"comment":"ok","stars":5},"timestamp":"1970-01-01T00:00:00.000Z","version":2}"#

    @Test("Each record's body states its event's version, 1 included, after its timestamp, byte for byte")
    func encodedVersion() throws {
        let plan = try TrackingPlan(schemas: [EarlierVersions.Rated.schema, Rated.schema, RatedAtVersionZero.schema, RatedAtVersionMinusOne.schema])
        let sut = CollectorBatchEncoder(plan: plan, instrument: NoOpInstrument())
        let batch = [
            EventRecord(id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!, event: EarlierVersions.Rated(stars: 4), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil),
            EventRecord(id: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!, event: Rated(stars: 5, comment: "ok"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil),
            EventRecord(id: UUID(uuidString: "00000000-0000-4000-8000-000000000003")!, event: RatedAtVersionZero(stars: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil),
            EventRecord(id: UUID(uuidString: "00000000-0000-4000-8000-000000000004")!, event: RatedAtVersionMinusOne(stars: 2), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil),
        ]
        let expected = Data(#"{"records":[{"context":{},"id":"00000000-0000-4000-8000-000000000001","isRedelivered":false,"name":"rated","properties":{"stars":4},"timestamp":"1970-01-01T00:00:00.000Z","version":1},{"context":{},"id":"00000000-0000-4000-8000-000000000002","isRedelivered":false,"name":"rated","properties":{"comment":"ok","stars":5},"timestamp":"1970-01-01T00:00:00.000Z","version":2},{"context":{},"id":"00000000-0000-4000-8000-000000000003","isRedelivered":false,"name":"rated","properties":{"stars":1},"timestamp":"1970-01-01T00:00:00.000Z","version":0},{"context":{},"id":"00000000-0000-4000-8000-000000000004","isRedelivered":false,"name":"rated","properties":{"stars":2},"timestamp":"1970-01-01T00:00:00.000Z","version":-1}]}"#.utf8)

        let actual = sut.batch(of: batch).body?.body

        #expect(actual == expected)
    }

    @Test("Records of one name at two versions decode into the type of each one's stated version, an earlier one in a private scope included")
    func statedVersions() throws {
        let plan = try TrackingPlan(schemas: [EarlierVersions.Rated.schema, Rated.schema])
        let sut = try CollectorBatchDecoder(plan: plan, events: [Rated.self, EarlierVersions.Rated.self], instrument: NoOpInstrument())
        let body = Data((#"{"records":["# + Self.v1 + "," + Self.v2 + "]}").utf8)
        let expectedFirst = EarlierVersions.Rated(stars: 4)
        let expectedSecond = Rated(stars: 5, comment: "ok")

        let actual = try sut.batch(from: body)

        try #require(actual.records.count == 2)
        #expect(actual.undecodedRecords.isEmpty)
        #expect(actual.records[0].event as? EarlierVersions.Rated == expectedFirst)
        #expect(actual.records[1].event as? Rated == expectedSecond)
    }

    @Test("Records of both versions encode again to the bytes they were read from")
    func roundTrip() throws {
        let plan = try TrackingPlan(schemas: [EarlierVersions.Rated.schema, Rated.schema])
        let sut = try CollectorBatchDecoder(plan: plan, events: [Rated.self, EarlierVersions.Rated.self], instrument: NoOpInstrument())
        let encoder = CollectorBatchEncoder(plan: plan, instrument: NoOpInstrument())
        let expected = Data((#"{"records":["# + Self.v1 + "," + Self.v2 + "]}").utf8)

        let decoded = try sut.batch(from: expected)
        let actual = encoder.batch(of: decoded.records).body?.body

        #expect(actual == expected)
    }

    @Test(
        "A record at a version the decoder has no type of, or the plan no schema of, is unknownVersion, and the records around it decode",
        arguments: [
            (3, [EarlierVersions.Rated.schema, Rated.schema, RatedAtVersionThree.schema]),
            (3, [EarlierVersions.Rated.schema, Rated.schema]),
            (0, [EarlierVersions.Rated.schema, Rated.schema]),
            (-1, [EarlierVersions.Rated.schema, Rated.schema]),
        ] as [(Int, [EventSchema])]
    )
    func unknownVersion(version: Int, schemas: [EventSchema]) throws {
        let plan = try TrackingPlan(schemas: schemas)
        let sut = try CollectorBatchDecoder(plan: plan, events: [Rated.self, EarlierVersions.Rated.self], instrument: NoOpInstrument())
        let record = #"{"context":{},"id":"00000000-0000-4000-8000-000000000002","isRedelivered":false,"name":"rated","properties":{"score":0.5},"timestamp":"1970-01-01T00:00:00.000Z","version":"# + String(version) + "}"
        let body = Data((#"{"records":["# + Self.v1 + "," + record + "," + Self.v2 + "]}").utf8)
        let expected = [UndecodedRecord(offset: 1, recordID: UUID(uuidString: "00000000-0000-4000-8000-000000000002"), eventName: "rated", reason: .unknownVersion(name: "rated", version: version))]
        let expectedIDs = [UUID(uuidString: "00000000-0000-4000-8000-000000000001"), UUID(uuidString: "00000000-0000-4000-8000-000000000003")]

        let actual = try sut.batch(from: body)

        #expect(actual.undecodedRecords == expected)
        #expect(actual.records.map(\.id) == expectedIDs.compactMap { $0 })
    }

    @Test("A record at version 3 is unknownVersion when the decoder has a type of it but the plan has no schema")
    func typeWithoutSchema() throws {
        let plan = try TrackingPlan(schemas: [Rated.schema])
        let sut = try CollectorBatchDecoder(plan: plan, events: [Rated.self, RatedAtVersionThree.self], instrument: NoOpInstrument())
        let body = Data(#"{"records":[{"context":{},"id":"00000000-0000-4000-8000-000000000002","isRedelivered":false,"name":"rated","properties":{"score":0.5},"timestamp":"1970-01-01T00:00:00.000Z","version":3}]}"#.utf8)
        let expected = [UndecodedRecord(offset: 0, recordID: UUID(uuidString: "00000000-0000-4000-8000-000000000002"), eventName: "rated", reason: .unknownVersion(name: "rated", version: 3))]

        let actual = try sut.batch(from: body)

        #expect(actual.undecodedRecords == expected)
        #expect(actual.records.isEmpty)
    }

    @Test("Version 0 and a negative version decode when the decoder has a type and the plan a schema of them")
    func zeroAndNegative() throws {
        let plan = try TrackingPlan(schemas: [RatedAtVersionZero.schema, RatedAtVersionMinusOne.schema])
        let sut = try CollectorBatchDecoder(plan: plan, events: [RatedAtVersionZero.self, RatedAtVersionMinusOne.self], instrument: NoOpInstrument())
        let body = Data(#"{"records":[{"context":{},"id":"00000000-0000-4000-8000-000000000001","isRedelivered":false,"name":"rated","properties":{"stars":1},"timestamp":"1970-01-01T00:00:00.000Z","version":0},{"context":{},"id":"00000000-0000-4000-8000-000000000002","isRedelivered":false,"name":"rated","properties":{"stars":2},"timestamp":"1970-01-01T00:00:00.000Z","version":-1}]}"#.utf8)
        let expectedVersions = [0, -1]

        let actual = try sut.batch(from: body)

        #expect(actual.undecodedRecords.isEmpty)
        #expect(actual.records.map { type(of: $0.event).schemaVersion } == expectedVersions)
    }

    @Test(
        "A version that is null, text, a boolean, a fraction, an array or past Int64 is malformedMember(version), and the records around it decode",
        arguments: ["null", #""2""#, "true", "2.5", "[2]", #"{}"#, "9223372036854775808", "1e20"]
    )
    func malformedVersion(version: String) throws {
        let plan = try TrackingPlan(schemas: [EarlierVersions.Rated.schema, Rated.schema])
        let sut = try CollectorBatchDecoder(plan: plan, events: [Rated.self, EarlierVersions.Rated.self], instrument: NoOpInstrument())
        let record = #"{"context":{},"id":"00000000-0000-4000-8000-000000000002","isRedelivered":false,"name":"rated","properties":{"stars":4},"timestamp":"1970-01-01T00:00:00.000Z","version":"# + version + "}"
        let body = Data((#"{"records":["# + Self.v1 + "," + record + "," + Self.v2 + "]}").utf8)
        let expected = [UndecodedRecord(offset: 1, recordID: UUID(uuidString: "00000000-0000-4000-8000-000000000002"), eventName: "rated", reason: .malformedMember("version"))]

        let actual = try sut.batch(from: body)

        #expect(actual.undecodedRecords == expected)
        #expect(actual.records.count == 2)
    }

    @Test("A version past Int32.max is unknownVersion where Int holds it, and malformedMember(version) on a 32-bit Int")
    func pastInt32() throws {
        let plan = try TrackingPlan(schemas: [EarlierVersions.Rated.schema, Rated.schema])
        let sut = try CollectorBatchDecoder(plan: plan, events: [Rated.self, EarlierVersions.Rated.self], instrument: NoOpInstrument())
        let body = Data(#"{"records":[{"context":{},"id":"00000000-0000-4000-8000-000000000002","isRedelivered":false,"name":"rated","properties":{"stars":4},"timestamp":"1970-01-01T00:00:00.000Z","version":2147483648}]}"#.utf8)
        let pastInt32: Int64 = 2_147_483_648
        let expectedReason = Int(exactly: pastInt32).map { CollectorDecodingError.unknownVersion(name: "rated", version: $0) } ?? .malformedMember("version")
        let expected = [UndecodedRecord(offset: 0, recordID: UUID(uuidString: "00000000-0000-4000-8000-000000000002"), eventName: "rated", reason: expectedReason)]

        let actual = try sut.batch(from: body)

        #expect(actual.undecodedRecords == expected)
    }

    @Test("A record without a version member, from a release before the member, decodes at version 1 when the decoder has version 1")
    func unstatedAtOne() throws {
        let plan = try TrackingPlan(schemas: [EarlierVersions.Rated.schema, Rated.schema])
        let sut = try CollectorBatchDecoder(plan: plan, events: [Rated.self, EarlierVersions.Rated.self], instrument: NoOpInstrument())
        let body = Data(#"{"records":[{"context":{},"id":"00000000-0000-4000-8000-000000000001","isRedelivered":false,"name":"rated","properties":{"stars":4},"timestamp":"1970-01-01T00:00:00.000Z"}]}"#.utf8)
        let expected = EarlierVersions.Rated(stars: 4)

        let actual = try sut.batch(from: body)

        #expect(actual.undecodedRecords.isEmpty)
        #expect(actual.records.first?.event as? EarlierVersions.Rated == expected)
    }

    @Test("A record without a version member decodes at version 1, not a lower version, when the decoder can read both")
    func unstatedAtOneOverLower() throws {
        let plan = try TrackingPlan(schemas: [RatedAtVersionMinusOne.schema, EarlierVersions.Rated.schema])
        let sut = try CollectorBatchDecoder(plan: plan, events: [RatedAtVersionMinusOne.self, EarlierVersions.Rated.self], instrument: NoOpInstrument())
        let body = Data(#"{"records":[{"context":{},"id":"00000000-0000-4000-8000-000000000001","isRedelivered":false,"name":"rated","properties":{"stars":4},"timestamp":"1970-01-01T00:00:00.000Z"}]}"#.utf8)
        let expected = EarlierVersions.Rated(stars: 4)

        let actual = try sut.batch(from: body)

        #expect(actual.undecodedRecords.isEmpty)
        #expect(actual.records.first?.event as? EarlierVersions.Rated == expected)
    }

    @Test("A record without a version member, sent at a raised version before the member, is read as version 1 when its properties fit")
    func unstatedRaisedVersionFits() throws {
        let plan = try TrackingPlan(schemas: [EarlierVersions.Rated.schema, Rated.schema])
        let sut = try CollectorBatchDecoder(plan: plan, events: [Rated.self, EarlierVersions.Rated.self], instrument: NoOpInstrument())
        let body = Data(#"{"records":[{"context":{},"id":"00000000-0000-4000-8000-000000000001","isRedelivered":false,"name":"rated","properties":{"comment":"ok","stars":5},"timestamp":"1970-01-01T00:00:00.000Z"}]}"#.utf8)
        let expected = EarlierVersions.Rated(stars: 5)

        let actual = try sut.batch(from: body)

        #expect(actual.undecodedRecords.isEmpty)
        #expect(actual.records.first?.event as? EarlierVersions.Rated == expected)
    }

    @Test("A record without a version member, sent at a raised version before the member, is read at version 1 and reported when it doesn't fit")
    func unstatedRaisedVersion() throws {
        let plan = try TrackingPlan(schemas: [EarlierVersions.Rated.schema, RatedAtVersionThree.schema])
        let sut = try CollectorBatchDecoder(plan: plan, events: [RatedAtVersionThree.self, EarlierVersions.Rated.self], instrument: NoOpInstrument())
        let body = Data(#"{"records":[{"context":{},"id":"00000000-0000-4000-8000-000000000001","isRedelivered":false,"name":"rated","properties":{"score":0.5},"timestamp":"1970-01-01T00:00:00.000Z"}]}"#.utf8)
        let expected = [UndecodedRecord(offset: 0, recordID: UUID(uuidString: "00000000-0000-4000-8000-000000000001"), eventName: "rated", reason: .undecodableProperty(event: "rated", property: "stars"))]

        let actual = try sut.batch(from: body)

        #expect(actual.undecodedRecords == expected)
    }

    @Test("A record without a version member decodes at the lowest version the decoder can read when it can't read version 1")
    func unstatedAtLowest() throws {
        let plan = try TrackingPlan(schemas: [Rated.schema, RatedAtVersionThree.schema])
        let sut = try CollectorBatchDecoder(plan: plan, events: [RatedAtVersionThree.self, Rated.self, EarlierVersions.Rated.self], instrument: NoOpInstrument())
        let body = Data(#"{"records":[{"context":{},"id":"00000000-0000-4000-8000-000000000001","isRedelivered":false,"name":"rated","properties":{"comment":"ok","stars":5},"timestamp":"1970-01-01T00:00:00.000Z"}]}"#.utf8)
        let expected = Rated(stars: 5, comment: "ok")

        let actual = try sut.batch(from: body)

        #expect(actual.undecodedRecords.isEmpty)
        #expect(actual.records.first?.event as? Rated == expected)
    }

    @Test("A record without a version member is unknownVersion at version 1 when the decoder can read no version of its event")
    func unstatedNoneReadable() throws {
        let plan = try TrackingPlan(schemas: [])
        let sut = try CollectorBatchDecoder(plan: plan, events: [Rated.self], instrument: NoOpInstrument())
        let body = Data(#"{"records":[{"context":{},"id":"00000000-0000-4000-8000-000000000001","isRedelivered":false,"name":"rated","properties":{"comment":"ok","stars":5},"timestamp":"1970-01-01T00:00:00.000Z"}]}"#.utf8)
        let expected = [UndecodedRecord(offset: 0, recordID: UUID(uuidString: "00000000-0000-4000-8000-000000000001"), eventName: "rated", reason: .unknownVersion(name: "rated", version: 1))]

        let actual = try sut.batch(from: body)

        #expect(actual.undecodedRecords == expected)
    }

    @Test("A record of an event the decoder has no type of is unknownEvent, whatever version it states")
    func unknownEventWithVersion() throws {
        let plan = try TrackingPlan(schemas: [Rated.schema])
        let sut = try CollectorBatchDecoder(plan: plan, events: [Rated.self], instrument: NoOpInstrument())
        let body = Data(#"{"records":[{"context":{},"id":"00000000-0000-4000-8000-000000000001","isRedelivered":false,"name":"refunded","properties":{},"timestamp":"1970-01-01T00:00:00.000Z","version":2}]}"#.utf8)
        let expected = [UndecodedRecord(offset: 0, recordID: UUID(uuidString: "00000000-0000-4000-8000-000000000001"), eventName: "refunded", reason: .unknownEvent(name: "refunded"))]

        let actual = try sut.batch(from: body)

        #expect(actual.undecodedRecords == expected)
    }

    @Test("Event types of one name at different versions don't throw, in either order")
    func versionsOfOneName() throws {
        let plan = try TrackingPlan(schemas: [EarlierVersions.Rated.schema, Rated.schema])
        let body = Data((#"{"records":["# + Self.v1 + "," + Self.v2 + "]}").utf8)
        let expectedVersions = [1, 2]

        let forward = try CollectorBatchDecoder(plan: plan, events: [EarlierVersions.Rated.self, Rated.self], instrument: NoOpInstrument())
        let backward = try CollectorBatchDecoder(plan: plan, events: [Rated.self, EarlierVersions.Rated.self], instrument: NoOpInstrument())
        let actualForward = try forward.batch(from: body).records.map { type(of: $0.event).schemaVersion }
        let actualBackward = try backward.batch(from: body).records.map { type(of: $0.event).schemaVersion }

        #expect(actualForward == expectedVersions)
        #expect(actualBackward == expectedVersions)
    }

    @Test("Two event types of one name at version 2 throw duplicateEvent with version 2, though another version of the name comes between")
    func duplicateAtVersion() throws {
        let plan = try TrackingPlan(schemas: [Rated.schema])
        let expected = CollectorBatchDecoderError.duplicateEvent(
            "rated",
            version: 2,
            firstType: String(reflecting: Rated.self),
            secondType: String(reflecting: RatedAgain.self)
        )

        #expect(throws: expected) {
            try CollectorBatchDecoder(plan: plan, events: [Rated.self, EarlierVersions.Rated.self, RatedAgain.self], instrument: NoOpInstrument())
        }
    }

    @Event(name: "rated", version: 2)
    struct RatedAgain {
        var stars: Int
    }
}
