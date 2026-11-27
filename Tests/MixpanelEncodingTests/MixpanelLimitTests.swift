import DestinationTesting
import Events
import Foundation
import HTTPDestinations
import Instrumentation
import MixpanelEncoding
import Sessions
import Testing
import TrackingPlans

@Suite("MixpanelBatchEncoder: Mixpanel's limits on an event")
struct MixpanelLimitTests {
    struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }

        init(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            nil
        }
    }

    /// An event of `count` integer properties, `p000` onward.
    struct Wide: Event, Encodable {
        static let name = "wide"

        var count: Int

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: Key.self)
            for index in 0 ..< count {
                try container.encode(index, forKey: Key(stringValue: String(format: "p%03d", index)))
            }
        }
    }

    /// A value that nests `depth` objects, each with one member `a`, around an integer.
    struct Nest: Encodable {
        var depth: Int

        func encode(to encoder: any Encoder) throws {
            if depth == 0 {
                var container = encoder.singleValueContainer()
                try container.encode(1)
            } else {
                var container = encoder.container(keyedBy: Key.self)
                try container.encode(Nest(depth: depth - 1), forKey: Key(stringValue: "a"))
            }
        }
    }

    /// An event with one property, `value`, that the test gives.
    struct Holding<Value: Encodable & Sendable>: Event, Encodable {
        static var name: String { "holding" }

        var value: Value
    }

    @Test("A record of 254 properties, counting the encoder's 5 members, is sent")
    func propertiesBelowLimitSent() throws {
        let schema = EventSchema(name: "wide", version: 1, consentCategory: .analytics, properties: [])
        let sut = MixpanelBatchEncoder(projectToken: "testprojecttoken", plan: try TrackingPlan(schemas: [schema]))
        let record = EventRecord(event: Wide(count: 249), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expectedRequestCount = 1

        let actual = sut.requests(for: [record])

        #expect(actual.requests.count == expectedRequestCount)
        #expect(actual.skippedRecords.isEmpty)
    }

    @Test("A record of 255 properties, counting the encoder's 5 members, is left out as tooManyProperties with the count")
    func propertiesAtLimitSkipped() throws {
        let schema = EventSchema(name: "wide", version: 1, consentCategory: .analytics, properties: [])
        let sut = MixpanelBatchEncoder(projectToken: "testprojecttoken", plan: try TrackingPlan(schemas: [schema]))
        let record = EventRecord(event: Wide(count: 250), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expected = [SkippedRecord<MixpanelEncodingError>(recordID: record.id, eventName: "wide", schemaVersion: 1, reason: .tooManyProperties(event: "wide", count: 255))]

        let actual = sut.requests(for: [record])

        #expect(actual.requests.isEmpty)
        #expect(actual.skippedRecords == expected)
    }

    @Test("A session's $device_id counts toward the 255 properties: 249 of the event's own with a session make 255")
    func deviceIDCounted() throws {
        let schema = EventSchema(name: "wide", version: 1, consentCategory: .analytics, properties: [])
        let sut = MixpanelBatchEncoder(projectToken: "testprojecttoken", plan: try TrackingPlan(schemas: [schema]))
        var context = ServiceContext.topLevel
        context[SessionKey.self] = UUID()
        let record = EventRecord(event: Wide(count: 249), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil, context: context)
        let expected = [SkippedRecord<MixpanelEncodingError>(recordID: record.id, eventName: "wide", schemaVersion: 1, reason: .tooManyProperties(event: "wide", count: 255))]

        let actual = sut.requests(for: [record]).skippedRecords

        #expect(actual == expected)
    }

    @Test("A record holding an array of 254 elements is sent")
    func arrayBelowLimitSent() throws {
        let schema = EventSchema(name: "holding", version: 1, consentCategory: .analytics, properties: [])
        let sut = MixpanelBatchEncoder(projectToken: "testprojecttoken", plan: try TrackingPlan(schemas: [schema]))
        let record = EventRecord(event: Holding(value: [Int](repeating: 1, count: 254)), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expectedRequestCount = 1

        let actual = sut.requests(for: [record])

        #expect(actual.requests.count == expectedRequestCount)
        #expect(actual.skippedRecords.isEmpty)
    }

    @Test("A record holding an array of 255 elements is left out as tooManyArrayElements, naming the property and the count")
    func arrayAtLimitSkipped() throws {
        let schema = EventSchema(name: "holding", version: 1, consentCategory: .analytics, properties: [])
        let sut = MixpanelBatchEncoder(projectToken: "testprojecttoken", plan: try TrackingPlan(schemas: [schema]))
        let record = EventRecord(event: Holding(value: [Int](repeating: 1, count: 255)), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expected = [SkippedRecord<MixpanelEncodingError>(recordID: record.id, eventName: "holding", schemaVersion: 1, reason: .tooManyArrayElements(event: "holding", property: "value", count: 255))]

        let actual = sut.requests(for: [record])

        #expect(actual.requests.isEmpty)
        #expect(actual.skippedRecords == expected)
    }

    @Test("An array of 255 elements inside an object in a property is left out as tooManyArrayElements, naming the property")
    func arrayInObjectSkipped() throws {
        let schema = EventSchema(name: "holding", version: 1, consentCategory: .analytics, properties: [])
        let sut = MixpanelBatchEncoder(projectToken: "testprojecttoken", plan: try TrackingPlan(schemas: [schema]))
        let record = EventRecord(event: Holding(value: ["items": [Int](repeating: 1, count: 255)]), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expected = [SkippedRecord<MixpanelEncodingError>(recordID: record.id, eventName: "holding", schemaVersion: 1, reason: .tooManyArrayElements(event: "holding", property: "value", count: 255))]

        let actual = sut.requests(for: [record]).skippedRecords

        #expect(actual == expected)
    }

    @Test("An array of 255 elements inside a shorter array is left out as tooManyArrayElements with the longer count")
    func arrayInArraySkipped() throws {
        let schema = EventSchema(name: "holding", version: 1, consentCategory: .analytics, properties: [])
        let sut = MixpanelBatchEncoder(projectToken: "testprojecttoken", plan: try TrackingPlan(schemas: [schema]))
        let record = EventRecord(event: Holding(value: [[Int](repeating: 1, count: 255)]), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expected = [SkippedRecord<MixpanelEncodingError>(recordID: record.id, eventName: "holding", schemaVersion: 1, reason: .tooManyArrayElements(event: "holding", property: "value", count: 255))]

        let actual = sut.requests(for: [record]).skippedRecords

        #expect(actual == expected)
    }

    @Test("Of two properties holding arrays of 255 elements or more, the first in the order of the names' UTF-8 bytes is named")
    func firstPropertyNamed() throws {
        struct TwoLists: Event, Encodable {
            static let name = "two_lists"

            var zebra = [Int](repeating: 1, count: 300)
            var apple = [Int](repeating: 1, count: 255)
        }
        let schema = EventSchema(name: "two_lists", version: 1, consentCategory: .analytics, properties: [])
        let sut = MixpanelBatchEncoder(projectToken: "testprojecttoken", plan: try TrackingPlan(schemas: [schema]))
        let record = EventRecord(event: TwoLists(), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expected = [SkippedRecord<MixpanelEncodingError>(recordID: record.id, eventName: "two_lists", schemaVersion: 1, reason: .tooManyArrayElements(event: "two_lists", property: "apple", count: 255))]

        let actual = sut.requests(for: [record]).skippedRecords

        #expect(actual == expected)
    }

    @Test("A property nesting objects 3 deep is sent")
    func depthAtLimitSent() throws {
        let schema = EventSchema(name: "holding", version: 1, consentCategory: .analytics, properties: [])
        let sut = MixpanelBatchEncoder(projectToken: "testprojecttoken", plan: try TrackingPlan(schemas: [schema]))
        let record = EventRecord(event: Holding(value: Nest(depth: 3)), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expectedRequestCount = 1

        let actual = sut.requests(for: [record])

        #expect(actual.requests.count == expectedRequestCount)
        #expect(actual.skippedRecords.isEmpty)
    }

    @Test("A property nesting objects 4 deep is left out as nestedTooDeeply, naming the property")
    func depthPastLimitSkipped() throws {
        let schema = EventSchema(name: "holding", version: 1, consentCategory: .analytics, properties: [])
        let sut = MixpanelBatchEncoder(projectToken: "testprojecttoken", plan: try TrackingPlan(schemas: [schema]))
        let record = EventRecord(event: Holding(value: Nest(depth: 4)), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expected = [SkippedRecord<MixpanelEncodingError>(recordID: record.id, eventName: "holding", schemaVersion: 1, reason: .nestedTooDeeply(event: "holding", property: "value"))]

        let actual = sut.requests(for: [record])

        #expect(actual.requests.isEmpty)
        #expect(actual.skippedRecords == expected)
    }

    @Test("An array adds no depth: an array of objects nested 3 deep is sent")
    func arrayAddsNoDepth() throws {
        let schema = EventSchema(name: "holding", version: 1, consentCategory: .analytics, properties: [])
        let sut = MixpanelBatchEncoder(projectToken: "testprojecttoken", plan: try TrackingPlan(schemas: [schema]))
        let record = EventRecord(event: Holding(value: [Nest(depth: 3)]), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expectedRequestCount = 1

        let actual = sut.requests(for: [record])

        #expect(actual.requests.count == expectedRequestCount)
        #expect(actual.skippedRecords.isEmpty)
    }

    @Test("Objects nested 4 deep inside an array are left out as nestedTooDeeply")
    func depthInArraySkipped() throws {
        let schema = EventSchema(name: "holding", version: 1, consentCategory: .analytics, properties: [])
        let sut = MixpanelBatchEncoder(projectToken: "testprojecttoken", plan: try TrackingPlan(schemas: [schema]))
        let record = EventRecord(event: Holding(value: [Nest(depth: 1), Nest(depth: 4)]), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expected = [SkippedRecord<MixpanelEncodingError>(recordID: record.id, eventName: "holding", schemaVersion: 1, reason: .nestedTooDeeply(event: "holding", property: "value"))]

        let actual = sut.requests(for: [record]).skippedRecords

        #expect(actual == expected)
    }

    @Test("The deepest member of an object sets its depth, not the first: an object of a scalar and a member 4 deep is left out")
    func deepestMemberCounts() throws {
        struct Mixed: Encodable {
            var shallow = 1
            var deep = Nest(depth: 3)
        }
        let schema = EventSchema(name: "holding", version: 1, consentCategory: .analytics, properties: [])
        let sut = MixpanelBatchEncoder(projectToken: "testprojecttoken", plan: try TrackingPlan(schemas: [schema]))
        let record = EventRecord(event: Holding(value: Mixed()), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expected = [SkippedRecord<MixpanelEncodingError>(recordID: record.id, eventName: "holding", schemaVersion: 1, reason: .nestedTooDeeply(event: "holding", property: "value"))]

        let actual = sut.requests(for: [record]).skippedRecords

        #expect(actual == expected)
    }

    @Test("The factory succeeds for a plan with a property Mixpanel reserves, which it logs rather than throws for")
    func reservedSchemaPropertyStillSetsUp() throws {
        let schema = EventSchema(name: "video_watched", version: 1, consentCategory: .analytics, properties: [EventSchema.Property(name: "time", typeName: "Double", isOptional: false)])
        let plan = try TrackingPlan(schemas: [schema])
        let transport = ScriptedTransport([.status(.ok)])

        #expect(throws: Never.self) {
            try HTTPDestination.mixpanel(projectToken: "testprojecttoken", region: .us, plan: plan, transport: transport)
        }
    }
}
