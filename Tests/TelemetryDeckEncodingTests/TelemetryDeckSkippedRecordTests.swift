import EventMacros
import Foundation
import HTTPDestinations
import Instrumentation
import Sessions
import TelemetryDeckEncoding
import Testing
import TrackingPlans

// TelemetryDeck's rules are Ingest API v3's (https://telemetrydeck.com/docs/ingest/v3/, read
// 2026-11-27): "A type may only contain letters, digits, dots, underscores, and hyphens", the same
// of every key, and a receivedAt it can parse. The endpoint, the same day, answered 422 for a key
// `bé` and an empty key, and for a receivedAt of 0000-12-31T23:59:59.999Z, and took
// 0001-01-01T00:00:00.000Z. v3 reserves the `TelemetryDeck.` scope ("avoid using parameter names
// that begin with the `TelemetryDeck.` scope"), and its event members sit beside the parameters in
// the flat event: appID, clientUser and receivedAt required, type, sessionID, isTestMode and
// floatValue optional. It renames no key and rejects no other name.
// Private: its events share their names with other events of this test target, and @Event
// leaves a private type's events out of the link check of names (DefiningEvents, Limits).
@Suite("TelemetryDeckBatchEncoder: skipped records")
private struct TelemetryDeckSkippedRecordTests {
    @Event(name: "checkout_started", version: 2)
    struct CheckoutStarted {
        var cartSize: Int
    }

    @Event(name: "measured")
    struct Measured {
        var value: Double
    }

    struct Cart: Codable, Hashable {
        var size: Int
    }

    @Event(name: "cart_viewed")
    struct CartViewed {
        var cart: Cart
        var cartSize: Int
    }

    struct HandWritten: Event {
        var plan: String
    }

    /// An event named by its test: a task-local, so tests running in parallel each see their own.
    struct Named: Event, Codable {
        @TaskLocal static var testName = "named"

        static var name: String { testName }

        init() {}
    }

    /// An event named by its test that isn't `Encodable`.
    struct NamedHandWritten: Event {
        static var name: String { Named.testName }
    }

    /// An event of the properties its test gives, by name, which only a hand-written `Encodable`
    /// conformance can write when a name isn't a Swift identifier.
    struct PropertiesNamed: Event, Encodable {
        static let name = "properties_named"

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

        var properties: [String: String]

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: Key.self)
            for (name, value) in properties {
                try container.encode(value, forKey: Key(stringValue: name))
            }
        }
    }

    @Test("A record whose event the plan doesn't describe is left out as unknownEvent, and the records around it are sent")
    func unknownEvent() throws {
        let sut = try TelemetryDeckBatchEncoder(appID: "B97579B6-FFB8-4AC5-AAA7-DA5796CC5DCE", testMode: false, plan: try TrackingPlan(schemas: [CheckoutStarted.schema]))
        var context = ServiceContext.topLevel
        context[SessionKey.self] = UUID()
        let skipped = EventRecord(event: Measured(value: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_608), sourceLocation: nil, context: context)
        let batch = [
            EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil, context: context),
            skipped,
            EventRecord(event: CheckoutStarted(cartSize: 3), timestamp: Date(timeIntervalSince1970: 1_795_442_609), sourceLocation: nil, context: context),
        ]
        let expectedBody = try #require(sut.requests(for: [batch[0], batch[2]]).requests.first).body
        let expectedSkipped = [SkippedRecord<TelemetryDeckEncodingError>(recordID: skipped.id, eventName: "measured", schemaVersion: 1, reason: .unknownEvent(name: "measured", version: 1))]

        let actual = sut.requests(for: batch)

        #expect(actual.requests.map(\.body) == [expectedBody])
        #expect(actual.skippedRecords == expectedSkipped)
    }

    @Test("A record whose version the plan doesn't describe is left out as unknownEvent with its version, though the plan has its name")
    func unknownVersion() throws {
        let earlier = EventSchema(name: "checkout_started", version: 1, consentCategory: .analytics, properties: [])
        let sut = try TelemetryDeckBatchEncoder(appID: "B97579B6-FFB8-4AC5-AAA7-DA5796CC5DCE", testMode: false, plan: try TrackingPlan(schemas: [earlier]))
        let record = EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expected = [SkippedRecord<TelemetryDeckEncodingError>(recordID: record.id, eventName: "checkout_started", schemaVersion: 2, reason: .unknownEvent(name: "checkout_started", version: 2))]

        let actual = sut.requests(for: [record]).skippedRecords

        #expect(actual == expected)
    }

    @Test("An event name of anything but ASCII letters, digits, '.', '_' and '-' is left out as invalidEventName, and one of only those is sent", arguments: [
        ("Order Completed", true), ("café", true), ("a/b", true), ("a:b", true), ("a\u{0}", true), ("😀", true), ("a+b", true),
        ("a", false), ("Z", false), ("0", false), (".", false), ("_", false), ("-", false), ("Az09._-", false), ("Actions.LoginView.loginButtonSucceeded", false),
    ])
    func invalidEventName(name: String, skipped: Bool) throws {
        let schema = EventSchema(name: name, version: 1, consentCategory: .analytics, properties: [])
        let sut = try TelemetryDeckBatchEncoder(appID: "B97579B6-FFB8-4AC5-AAA7-DA5796CC5DCE", testMode: false, plan: try TrackingPlan(schemas: [schema]))
        let record = Named.$testName.withValue(name) {
            EventRecord(event: Named(), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        }
        let expected: [TelemetryDeckEncodingError] = skipped ? [.invalidEventName(name: name)] : []

        let actual = Named.$testName.withValue(name) { sut.requests(for: [record]) }

        #expect(actual.skippedRecords.map(\.reason) == expected)
        #expect(actual.requests.flatMap(\.recordIDs) == (skipped ? [] : [record.id]))
    }

    @Test("An event name in the TelemetryDeck. scope, in any case, is left out as reservedEventName, and any other, an event member's name or a deprecated v2 parameter's included, is sent", arguments: [
        ("TelemetryDeck.Session.started", true), ("telemetrydeck.custom", true), ("TELEMETRYDECK.", true), ("TelemetryDeck.", true), ("tELEMETRYdECK.x", true),
        ("TelemetryDeck", false), ("TelemetryDeck_", false), ("TelemetryDeckSession", false), ("My.TelemetryDeck.event", false), (".TelemetryDeck.x", false),
        ("TelemetryDec.x", false), ("type", false), ("appID", false), ("clientUser", false), ("floatValue", false), ("platform", false), ("count", false),
    ])
    func reservedEventName(name: String, skipped: Bool) throws {
        let schema = EventSchema(name: name, version: 1, consentCategory: .analytics, properties: [])
        let sut = try TelemetryDeckBatchEncoder(appID: "B97579B6-FFB8-4AC5-AAA7-DA5796CC5DCE", testMode: false, plan: try TrackingPlan(schemas: [schema]))
        let record = Named.$testName.withValue(name) {
            EventRecord(event: Named(), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        }
        let expected: [TelemetryDeckEncodingError] = skipped ? [.reservedEventName(name: name)] : []

        let actual = Named.$testName.withValue(name) { sut.requests(for: [record]) }

        #expect(actual.skippedRecords.map(\.reason) == expected)
        #expect(actual.requests.flatMap(\.recordIDs) == (skipped ? [] : [record.id]))
    }

    @Test("A parameter name of anything but ASCII letters, digits, '.', '_' and '-', or none, is left out as invalidParameterName, and one of only those is sent", arguments: [
        ("bé", true), ("a b", true), ("", true), ("a:b", true), ("a/b", true), ("a\u{0}", true), ("😀", true),
        ("a", false), ("Z", false), ("0", false), ("Az09._-", false), ("Shop.Cart.size", false), ("-", false),
    ])
    func invalidParameterName(name: String, skipped: Bool) throws {
        let schema = EventSchema(name: "properties_named", version: 1, consentCategory: .analytics, properties: [])
        let sut = try TelemetryDeckBatchEncoder(appID: "B97579B6-FFB8-4AC5-AAA7-DA5796CC5DCE", testMode: false, plan: try TrackingPlan(schemas: [schema]))
        let record = EventRecord(event: PropertiesNamed(properties: [name: "v"]), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expected: [TelemetryDeckEncodingError] = skipped ? [.invalidParameterName(event: "properties_named", parameter: name)] : []

        let actual = sut.requests(for: [record])

        #expect(actual.skippedRecords.map(\.reason) == expected)
        #expect(actual.requests.flatMap(\.recordIDs) == (skipped ? [] : [record.id]))
    }

    @Test("A parameter named exactly as an Ingest API v3 event member, or in the TelemetryDeck. scope in any case, is left out as reservedParameterName, and one only like it is sent", arguments: [
        ("appID", true), ("clientUser", true), ("receivedAt", true), ("type", true), ("sessionID", true), ("isTestMode", true), ("floatValue", true),
        ("TelemetryDeck.Device.platform", true), ("telemetrydeck.custom", true), ("TELEMETRYDECK.x", true), ("TelemetryDeck.", true),
        ("Type", false), ("TYPE", false), ("appId", false), ("APPID", false), ("sessionId", false), ("floatvalue", false), ("types", false),
        ("myType", false), ("Shop.type", false), ("type.name", false), ("TelemetryDeck", false), ("TelemetryDeckX", false), (".TelemetryDeck.x", false),
        ("count", false), ("platform", false), ("appVersion", false), ("locale", false), ("telemetryAPIVersion", false), ("newSessionBegan", false),
    ])
    func reservedParameterName(name: String, skipped: Bool) throws {
        let schema = EventSchema(name: "properties_named", version: 1, consentCategory: .analytics, properties: [])
        let sut = try TelemetryDeckBatchEncoder(appID: "B97579B6-FFB8-4AC5-AAA7-DA5796CC5DCE", testMode: false, plan: try TrackingPlan(schemas: [schema]))
        let record = EventRecord(event: PropertiesNamed(properties: [name: "v"]), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expected: [TelemetryDeckEncodingError] = skipped ? [.reservedParameterName(event: "properties_named", parameter: name)] : []

        let actual = sut.requests(for: [record])

        #expect(actual.skippedRecords.map(\.reason) == expected)
        #expect(actual.requests.flatMap(\.recordIDs) == (skipped ? [] : [record.id]))
    }

    @Test("Of several parameter names that break a rule, the first in UTF-8 order is reported, and a name TelemetryDeck refuses before one it reserves")
    func parameterNameOrder() throws {
        let schema = EventSchema(name: "properties_named", version: 1, consentCategory: .analytics, properties: [])
        let sut = try TelemetryDeckBatchEncoder(appID: "B97579B6-FFB8-4AC5-AAA7-DA5796CC5DCE", testMode: false, plan: try TrackingPlan(schemas: [schema]))
        let invalid = EventRecord(event: PropertiesNamed(properties: ["z z": "v", "b b": "v", "type": "v"]), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let reserved = EventRecord(event: PropertiesNamed(properties: ["type": "v", "sessionID": "v", "TelemetryDeck.x": "v", "appID": "v"]), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expected: [TelemetryDeckEncodingError] = [
            .invalidParameterName(event: "properties_named", parameter: "b b"),
            .reservedParameterName(event: "properties_named", parameter: "TelemetryDeck.x"),
        ]

        let actual = sut.requests(for: [invalid, reserved]).skippedRecords.map(\.reason)

        #expect(actual == expected)
    }

    // Twenty names a record, in three records, so a dictionary's own order can't match by chance.
    @Test("Of many parameter names TelemetryDeck refuses, the first in UTF-8 order is always the one reported")
    func parameterNameOrderOfMany() throws {
        let schema = EventSchema(name: "properties_named", version: 1, consentCategory: .analytics, properties: [])
        let sut = try TelemetryDeckBatchEncoder(appID: "B97579B6-FFB8-4AC5-AAA7-DA5796CC5DCE", testMode: false, plan: try TrackingPlan(schemas: [schema]))
        let letters = Array("abcdefghijklmnopqrst")
        let batch = ["", "x", "Q"].map { prefix in
            let properties = Dictionary(uniqueKeysWithValues: letters.map { ("\(prefix)\($0) \($0)", "v") })
            return EventRecord(event: PropertiesNamed(properties: properties), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        }
        let expected: [TelemetryDeckEncodingError] = [
            .invalidParameterName(event: "properties_named", parameter: "a a"),
            .invalidParameterName(event: "properties_named", parameter: "xa a"),
            .invalidParameterName(event: "properties_named", parameter: "Qa a"),
        ]

        let actual = sut.requests(for: batch).skippedRecords.map(\.reason)

        #expect(actual == expected)
    }

    @Test("A nested value is checked by its flattened name: a key TelemetryDeck refuses inside an object is left out as invalidParameterName")
    func nestedParameterName() throws {
        let schema = EventSchema(name: "properties_named", version: 1, consentCategory: .analytics, properties: [])
        let sut = try TelemetryDeckBatchEncoder(appID: "B97579B6-FFB8-4AC5-AAA7-DA5796CC5DCE", testMode: false, plan: try TrackingPlan(schemas: [schema]))
        let record = EventRecord(event: NestedProperty(member: "a b"), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expected: [TelemetryDeckEncodingError] = [.invalidParameterName(event: "properties_named", parameter: "meta.a b")]

        let actual = sut.requests(for: [record]).skippedRecords.map(\.reason)

        #expect(actual == expected)
    }

    /// An event of one object property, `meta`, holding one member named by the test.
    struct NestedProperty: Event, Encodable {
        static let name = "properties_named"

        var member: String

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: PropertiesNamed.Key.self)
            var nested = container.nestedContainer(keyedBy: PropertiesNamed.Key.self, forKey: PropertiesNamed.Key(stringValue: "meta"))
            try nested.encode("v", forKey: PropertiesNamed.Key(stringValue: member))
        }
    }

    @Test("A record whose values flatten to one parameter's name is left out as parameterNameCollision")
    func parameterNameCollision() throws {
        let schema = EventSchema(name: "properties_named", version: 1, consentCategory: .analytics, properties: [])
        let sut = try TelemetryDeckBatchEncoder(appID: "B97579B6-FFB8-4AC5-AAA7-DA5796CC5DCE", testMode: false, plan: try TrackingPlan(schemas: [schema]))
        let record = EventRecord(event: Colliding(), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expected = [SkippedRecord<TelemetryDeckEncodingError>(recordID: record.id, eventName: "properties_named", schemaVersion: 1, reason: .parameterNameCollision(event: "properties_named", parameter: "cart.size"))]

        let actual = sut.requests(for: [record])

        #expect(actual.skippedRecords == expected)
        #expect(actual.requests.isEmpty)
    }

    /// An event holding `cart.size` beside `cart`'s `size`, which flatten to one name.
    struct Colliding: Event, Encodable {
        static let name = "properties_named"

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: PropertiesNamed.Key.self)
            try container.encode(3, forKey: PropertiesNamed.Key(stringValue: "cart.size"))
            var cart = container.nestedContainer(keyedBy: PropertiesNamed.Key.self, forKey: PropertiesNamed.Key(stringValue: "cart"))
            try cart.encode(2, forKey: PropertiesNamed.Key(stringValue: "size"))
        }
    }

    @Test("An object property flattens to dotted names that don't collide with a property of a similar name")
    func flattenedWithoutCollision() throws {
        let sut = try TelemetryDeckBatchEncoder(appID: "B97579B6-FFB8-4AC5-AAA7-DA5796CC5DCE", testMode: false, plan: try TrackingPlan(schemas: [CartViewed.schema]))
        let record = EventRecord(event: CartViewed(cart: Cart(size: 2), cartSize: 3), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)

        let body = try #require(sut.requests(for: [record]).requests.first).body.body

        let event = try #require((try JSONSerialization.jsonObject(with: body) as? [[String: Any]])?.first)
        #expect(event["cart.size"] as? Int == 2)
        #expect(event["cartSize"] as? Int == 3)
        #expect(event["cart"] == nil)
    }

    @Test("A record whose event isn't Encodable is left out as notEncodable")
    func notEncodable() throws {
        let schema = EventSchema(name: "HandWritten", version: 1, consentCategory: .analytics, properties: [EventSchema.Property(name: "plan", typeName: "String", isOptional: false)])
        let sut = try TelemetryDeckBatchEncoder(appID: "B97579B6-FFB8-4AC5-AAA7-DA5796CC5DCE", testMode: false, plan: try TrackingPlan(schemas: [schema]))
        let record = EventRecord(event: HandWritten(plan: "pro"), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expected: [TelemetryDeckEncodingError] = [.notEncodable(name: "HandWritten")]

        let actual = sut.requests(for: [record]).skippedRecords.map(\.reason)

        #expect(actual == expected)
    }

    @Test("A record holding a value JSON can't is left out as unrepresentableValue", arguments: [Double.nan, .infinity, -.infinity])
    func unrepresentableValue(value: Double) throws {
        let sut = try TelemetryDeckBatchEncoder(appID: "B97579B6-FFB8-4AC5-AAA7-DA5796CC5DCE", testMode: false, plan: try TrackingPlan(schemas: [Measured.schema]))
        let record = EventRecord(event: Measured(value: value), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expected: [TelemetryDeckEncodingError] = [.unrepresentableValue(event: "measured", property: "value")]

        let actual = sut.requests(for: [record]).skippedRecords.map(\.reason)

        #expect(actual == expected)
    }

    @Test("A record whose name TelemetryDeck refuses is left out as invalidEventName, though it can't be read either")
    func invalidNameBeforeReading() throws {
        let schema = EventSchema(name: "Order Completed", version: 1, consentCategory: .analytics, properties: [EventSchema.Property(name: "plan", typeName: "String", isOptional: false)])
        let sut = try TelemetryDeckBatchEncoder(appID: "B97579B6-FFB8-4AC5-AAA7-DA5796CC5DCE", testMode: false, plan: try TrackingPlan(schemas: [schema]))
        let record = Named.$testName.withValue("Order Completed") {
            EventRecord(event: NamedHandWritten(), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        }
        let expected: [TelemetryDeckEncodingError] = [.invalidEventName(name: "Order Completed")]

        let actual = Named.$testName.withValue("Order Completed") { sut.requests(for: [record]).skippedRecords.map(\.reason) }

        #expect(actual == expected)
    }

    @Test("A record whose name TelemetryDeck reserves is left out as reservedEventName, though it can't be read either")
    func reservedNameBeforeReading() throws {
        let schema = EventSchema(name: "TelemetryDeck.custom", version: 1, consentCategory: .analytics, properties: [EventSchema.Property(name: "plan", typeName: "String", isOptional: false)])
        let sut = try TelemetryDeckBatchEncoder(appID: "B97579B6-FFB8-4AC5-AAA7-DA5796CC5DCE", testMode: false, plan: try TrackingPlan(schemas: [schema]))
        let record = Named.$testName.withValue("TelemetryDeck.custom") {
            EventRecord(event: NamedHandWritten(), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        }
        let expected: [TelemetryDeckEncodingError] = [.reservedEventName(name: "TelemetryDeck.custom")]

        let actual = Named.$testName.withValue("TelemetryDeck.custom") { sut.requests(for: [record]).skippedRecords.map(\.reason) }

        #expect(actual == expected)
    }

    @Test("A record the plan doesn't describe is left out as unknownEvent even when TelemetryDeck refuses its name")
    func unknownBeforeInvalidName() throws {
        let sut = try TelemetryDeckBatchEncoder(appID: "B97579B6-FFB8-4AC5-AAA7-DA5796CC5DCE", testMode: false, plan: try TrackingPlan(schemas: [CheckoutStarted.schema]))
        let record = Named.$testName.withValue("Order Completed") {
            EventRecord(event: Named(), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        }
        let expected: [TelemetryDeckEncodingError] = [.unknownEvent(name: "Order Completed", version: 1)]

        let actual = Named.$testName.withValue("Order Completed") { sut.requests(for: [record]).skippedRecords.map(\.reason) }

        #expect(actual == expected)
    }

    @Test("A record whose name TelemetryDeck refuses is left out as invalidEventName, before its parameters and its timestamp")
    func invalidNameFirst() throws {
        let schema = EventSchema(name: "Order Completed", version: 1, consentCategory: .analytics, properties: [])
        let sut = try TelemetryDeckBatchEncoder(appID: "B97579B6-FFB8-4AC5-AAA7-DA5796CC5DCE", testMode: false, plan: try TrackingPlan(schemas: [schema]))
        let record = Named.$testName.withValue("Order Completed") {
            EventRecord(event: Named(), timestamp: Date(timeIntervalSince1970: .nan), sourceLocation: nil)
        }
        let expected: [TelemetryDeckEncodingError] = [.invalidEventName(name: "Order Completed")]

        let actual = Named.$testName.withValue("Order Completed") { sut.requests(for: [record]).skippedRecords.map(\.reason) }

        #expect(actual == expected)
    }

    @Test("A record whose parameter name breaks a rule is left out for it before its timestamp")
    func parameterBeforeTimestamp() throws {
        let schema = EventSchema(name: "properties_named", version: 1, consentCategory: .analytics, properties: [])
        let sut = try TelemetryDeckBatchEncoder(appID: "B97579B6-FFB8-4AC5-AAA7-DA5796CC5DCE", testMode: false, plan: try TrackingPlan(schemas: [schema]))
        let record = EventRecord(event: PropertiesNamed(properties: ["type": "v"]), timestamp: Date(timeIntervalSince1970: .nan), sourceLocation: nil)
        let expected: [TelemetryDeckEncodingError] = [.reservedParameterName(event: "properties_named", parameter: "type")]

        let actual = sut.requests(for: [record]).skippedRecords.map(\.reason)

        #expect(actual == expected)
    }

    // 0001-01-01T00:00:00Z is 62,135,596,800 seconds before 1970 and 10000-01-01T00:00:00Z
    // 253,402,300,800 after it, in the proleptic Gregorian calendar.
    @Test("A timestamp from 0001-01-01 to the end of 9999 is sent, and one outside, NaN or infinite is left out as unrepresentableTimestamp", arguments: [
        (-62_135_596_800.001, true), (-62_135_596_800, false), (0, false), (253_402_300_799.999, false), (253_402_300_800, true),
        (-.infinity, true), (.infinity, true), (.nan, true), (-1e300, true), (1e300, true),
    ])
    func timestampBounds(seconds: Double, skipped: Bool) throws {
        let sut = try TelemetryDeckBatchEncoder(appID: "B97579B6-FFB8-4AC5-AAA7-DA5796CC5DCE", testMode: false, plan: try TrackingPlan(schemas: [CheckoutStarted.schema]))
        let record = EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: seconds), sourceLocation: nil)
        let expected: [TelemetryDeckEncodingError] = skipped ? [.unrepresentableTimestamp] : []

        let actual = sut.requests(for: [record])

        #expect(actual.skippedRecords.map(\.reason) == expected)
        #expect(actual.requests.flatMap(\.recordIDs) == (skipped ? [] : [record.id]))
    }

    @Test("The first and last timestamps sent are written with four-digit years", arguments: [
        (-62_135_596_800.0, "0001-01-01T00:00:00.000Z"), (253_402_300_799.0, "9999-12-31T23:59:59.000Z"),
    ])
    func timestampForms(seconds: Double, expected: String) throws {
        let sut = try TelemetryDeckBatchEncoder(appID: "B97579B6-FFB8-4AC5-AAA7-DA5796CC5DCE", testMode: false, plan: try TrackingPlan(schemas: [CheckoutStarted.schema]))
        let record = EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: seconds), sourceLocation: nil)

        let body = try #require(sut.requests(for: [record]).requests.first).body.body

        let event = try #require((try JSONSerialization.jsonObject(with: body) as? [[String: Any]])?.first)
        #expect(event["receivedAt"] as? String == expected)
    }
}
