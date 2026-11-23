// How a property's type as written maps to its JSON Schema, one type at a time.

import Events
import JSONSchema
import Testing
import TrackingPlans

@Suite("TrackingPlan: property types")
struct TrackingPlanPropertyTypeTests {
    static let mappings: [(String, JSONValue)] = [
        ("String", ["type": "string"]),
        ("Bool", ["type": "boolean"]),
        ("Double", ["type": "number"]),
        ("Float", ["type": "number"]),
        ("Int", ["type": "integer"]),
        ("Int64", ["type": "integer"]),
        ("Int32", ["type": "integer", "minimum": -2_147_483_648, "maximum": 2_147_483_647]),
        ("Int16", ["type": "integer", "minimum": -32768, "maximum": 32767]),
        ("Int8", ["type": "integer", "minimum": -128, "maximum": 127]),
        ("UInt", ["type": "integer", "minimum": 0]),
        ("UInt64", ["type": "integer", "minimum": 0]),
        ("UInt32", ["type": "integer", "minimum": 0, "maximum": 4_294_967_295]),
        ("UInt16", ["type": "integer", "minimum": 0, "maximum": 65535]),
        ("UInt8", ["type": "integer", "minimum": 0, "maximum": 255]),
        ("Date", ["type": "string", "format": "date-time"]),
        ("UUID", ["type": "string", "format": "uuid"]),
        ("Swift.String", ["type": "string"]),
        ("Foundation.Date", ["type": "string", "format": "date-time"]),
        ("FoundationEssentials.UUID", ["type": "string", "format": "uuid"]),
        ("[String]", ["type": "array", "items": ["type": "string"]]),
        ("Array<Int8>", ["type": "array", "items": ["type": "integer", "minimum": -128, "maximum": 127]]),
        ("Swift.Array<Bool>", ["type": "array", "items": ["type": "boolean"]]),
        ("[[Double]]", ["type": "array", "items": ["type": "array", "items": ["type": "number"]]]),
        ("[String?]", ["type": "array", "items": ["type": ["string", "null"]]]),
        ("[String]?", ["type": ["array", "null"], "items": ["type": "string"]]),
        ("String?", ["type": ["string", "null"]]),
        ("String!", ["type": ["string", "null"]]),
        ("Optional<Int>", ["type": ["integer", "null"]]),
        ("Swift.Optional<Int>", ["type": ["integer", "null"]]),
        ("Sensitive<String>", ["type": "string", "x-traffluent-sensitive": true]),
        ("Events.Sensitive<Int>", ["type": "integer", "x-traffluent-sensitive": true]),
        ("Traffluent.Sensitive<Bool>", ["type": "boolean", "x-traffluent-sensitive": true]),
        ("Sensitive<String?>", ["type": ["string", "null"], "x-traffluent-sensitive": true]),
        ("Sensitive<String>?", ["type": ["string", "null"], "x-traffluent-sensitive": true]),
        ("[Sensitive<String>]", ["type": "array", "items": ["type": "string", "x-traffluent-sensitive": true]]),
        ("Sensitive< [ UInt8 ] >", ["type": "array", "items": ["type": "integer", "minimum": 0, "maximum": 255], "x-traffluent-sensitive": true]),
    ]

    @Test("A property's type as written maps to its JSON Schema", arguments: mappings)
    func mapping(typeName: String, expected: JSONValue) throws {
        let sut = TrackingPlan(schemas: [EventSchema(name: "event", version: 1, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "value", typeName: typeName, isOptional: false),
        ])])
        let document = try JSONValue.parse(String(decoding: try #require(sut.files.last).contents, as: UTF8.self))

        let actual = document.object?["properties"]?.object?["value"]

        #expect(actual == expected)
    }

    static let unknowns: [(String, String)] = [
        ("Coordinate", "Coordinate"),
        ("MyApp.String", "MyApp.String"),
        ("Swift.Swift.String", "Swift.Swift.String"),
        ("Foundation.String", "Foundation.String"),
        ("Value", "Value"),
        ("Box<String>", "Box<String>"),
        ("Box< String ,Int >", "Box<String, Int>"),
        ("String<Int>", "String<Int>"),
        ("Sensitive<String, Int>", "Sensitive<String, Int>"),
        ("Array<Int, Int>", "Array<Int, Int>"),
        ("Optional<Int, Int>", "Optional<Int, Int>"),
        ("Sensitive", "Sensitive"),
        ("[String: Int]", "[String: Int]"),
        ("(Int, Int)", "(Int, Int)"),
        ("any Error", "any Error"),
        ("some Sequence", "some Sequence"),
        ("Box<Int?>", "Box<Int?>"),
        ("Box<[Int]>", "Box<[Int]>"),
        ("Box< My_Type >", "Box<My_Type>"),
        ("Box<String", "Box<String"),
        ("Box<", "Box<"),
        ("[Int", "[Int"),
        ("Int>", "Int>"),
        ("Swift.", "Swift."),
        ("9Lives", "9Lives"),
        ("", ""),
    ]

    @Test("A type the plan can't map accepts any value and records the type", arguments: unknowns)
    func unknown(typeName: String, expectedType: String) throws {
        let expected: JSONValue = ["x-traffluent-swift-type": .string(expectedType)]
        let sut = TrackingPlan(schemas: [EventSchema(name: "event", version: 1, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "value", typeName: typeName, isOptional: false),
        ])])
        let document = try JSONValue.parse(String(decoding: try #require(sut.files.last).contents, as: UTF8.self))

        let actual = document.object?["properties"]?.object?["value"]

        #expect(actual == expected)
    }

    @Test("An unknown type nested in a known one records the nested type, without its optional")
    func nestedUnknown() throws {
        let expected: JSONValue = ["type": ["array", "null"], "items": ["x-traffluent-swift-type": "Coordinate"]]
        let sut = TrackingPlan(schemas: [EventSchema(name: "event", version: 1, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "value", typeName: "[Coordinate?]", isOptional: true),
        ])])
        let document = try JSONValue.parse(String(decoding: try #require(sut.files.last).contents, as: UTF8.self))

        let actual = document.object?["properties"]?.object?["value"]

        #expect(actual == expected)
    }

    @Test("An optional property is nullable and not required; its type name doesn't repeat the optional")
    func optionalProperty() throws {
        let expectedProperty: JSONValue = ["type": ["integer", "null"], "minimum": 0, "maximum": 255]
        let expectedRequired: JSONValue = ["plan"]
        let sut = TrackingPlan(schemas: [EventSchema(name: "event", version: 1, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "plan", typeName: "String", isOptional: false),
            EventSchema.Property(name: "seats", typeName: "UInt8", isOptional: true),
        ])])
        let document = try JSONValue.parse(String(decoding: try #require(sut.files.last).contents, as: UTF8.self))

        let actualProperty = document.object?["properties"]?.object?["seats"]
        let actualRequired = document.object?["required"]

        #expect(actualProperty == expectedProperty)
        #expect(actualRequired == expectedRequired)
    }
}
