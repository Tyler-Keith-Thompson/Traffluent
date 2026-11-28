import EventMacros
import Events
import Foundation
import JSONValues
import PropertyJSON
import Testing
import TrackingPlans

@Suite("Event.init(properties:types:): an event read back from its properties as JSON")
struct EventPropertiesDecodingTests {
    enum NonEmpty: Refinement {
        static var constraints: [Constraint<String>] {
            get throws(InvalidConstraint) { try [.minLength(1)] }
        }
    }

    @Event(name: "shaped")
    struct Shaped {
        var name: String
        var nickname: String?
        var secret: Sensitive<String>
        var code: Refined<String, NonEmpty>
        var scores: [Int]
        var at: Date
        var ratio: Double
        var weight: Float
        var count: Int
    }

    static let properties: [String: JSON] = [
        "name": .string("Ada"),
        "nickname": .null,
        "secret": .string("s3cret"),
        "code": .string("A1"),
        "scores": .array([.integer(1), .integer(-2)]),
        "at": .string("2001-01-01T00:00:01.500Z"),
        "ratio": .integer(2),
        "weight": .number(0.1),
        "count": .integer(-7),
    ]

    @Test("Each shape reads back: a null optional as nil, a Sensitive and a Refined as their values, an array, a date, and whole and fractional floating-point numbers")
    func handWorked() throws {
        let expectedDate = Date(timeIntervalSinceReferenceDate: 1.5)
        let expectedWeight: Float = 0.1

        let actual = try Shaped(properties: Self.properties, types: Shaped.schema.propertyTypes)

        #expect(actual.name == "Ada")
        #expect(actual.nickname == nil)
        #expect(actual.secret.value == "s3cret")
        #expect(actual.code.value == "A1")
        #expect(actual.scores == [1, -2])
        #expect(actual.at == expectedDate)
        #expect(actual.ratio == 2)
        #expect(actual.weight == expectedWeight)
        #expect(actual.count == -7)
    }

    @Test("A present optional reads back as its value")
    func presentOptional() throws {
        var properties = Self.properties
        properties["nickname"] = .string("Countess")

        let actual = try Shaped(properties: properties, types: Shaped.schema.propertyTypes)

        #expect(actual.nickname == "Countess")
    }

    @Test(
        "A value that isn't what its property's type reads throws UndecodableProperty naming the property",
        arguments: [
            ("at", JSON.string("2001-01-01T00:00:01Z")),
            ("at", .number(1.5)),
            ("ratio", .string("2")),
            ("weight", .null),
            ("scores", .integer(1)),
            ("scores", .array([.string("1")])),
            ("code", .string("")),
            ("count", .number(1.5)),
            ("name", .integer(1)),
        ]
    )
    func mismatch(property: String, value: JSON) throws {
        var properties = Self.properties
        properties[property] = value
        let expected = UndecodableProperty(property: property)

        #expect(throws: expected) {
            try Shaped(properties: properties, types: Shaped.schema.propertyTypes)
        }
    }

    @Test("A missing required property, a redacted Sensitive one among them, throws UndecodableProperty naming it", arguments: ["name", "secret", "at"])
    func missing(property: String) throws {
        var properties = Self.properties
        properties[property] = nil
        let expected = UndecodableProperty(property: property)

        #expect(throws: expected) {
            try Shaped(properties: properties, types: Shaped.schema.propertyTypes)
        }
    }

    @Test("Without its written type, a whole number reads as an integer, so a Double property throws")
    func untyped() throws {
        var types = Shaped.schema.propertyTypes
        types["ratio"] = nil
        let expected = UndecodableProperty(property: "ratio")

        #expect(throws: expected) {
            try Shaped(properties: Self.properties, types: types)
        }
    }
}
