// What @Event generates, compiled by the real compiler and run: names, consent categories,
// schemas and the coding, through the CBOR package a store writes with, against hand-worked bytes.

import CBOR
import EventMacros
import Testing

@Suite("@Event")
struct EventMacroTests {
    @Event
    struct SignedUp {
        var plan: String
        var seats: Int?
    }

    @Event(name: "ad_clicked", consent: .advertising, version: 3)
    struct AdClicked {
        var campaign: String
    }

    @Event(consent: ConsentCategory("crash-reports"))
    struct Crashed {}

    @Event
    struct Shapes {
        var count: Int
        var tags: [String]
        var ratio: Double!
        var wrapped: Optional<Bool>
        var qualified: Swift.Optional<Int8>
        var `default`: UInt8
        var encoder: Int16
        var decoder: Int16
        var map: Int16
        var first, second: UInt16
        let fixed = 7
        let assigned: Bool
        static let shared = 1
        var computed: Int { count * 2 }
        var observed: Int32 = 0 {
            didSet {}
        }
    }

    @Event
    struct Box<Value: Codable & Sendable> {
        var value: Value
    }

    @Event
    public struct Published {
        public var value: Int
    }

    @Test("An event's name is its type's name unless the macro names it")
    func names() {
        let expected = ["SignedUp", "ad_clicked"]

        let actual = [SignedUp.name, AdClicked.name]

        #expect(actual == expected)
    }

    @Test("An event's consent category is analytics unless the macro gives one")
    func consentCategories() {
        let expected = [ConsentCategory.analytics, .advertising, ConsentCategory("crash-reports")]

        let actual = [SignedUp.consentCategory, AdClicked.consentCategory, Crashed.consentCategory]

        #expect(actual == expected)
    }

    @Test("The schema holds the name, the version and each stored property's name, type and optionality in declaration order")
    func schema() {
        let expected = EventSchema(name: "SignedUp", version: 1, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "plan", typeName: "String", isOptional: false),
            EventSchema.Property(name: "seats", typeName: "Int", isOptional: true),
        ])

        let actual = SignedUp.schema

        #expect(actual == expected)
    }

    @Test("The schema takes the macro's name, version and consent category")
    func schemaNameAndVersion() {
        let expected = EventSchema(name: "ad_clicked", version: 3, consentCategory: .advertising, properties: [
            EventSchema.Property(name: "campaign", typeName: "String", isOptional: false),
        ])

        let actual = AdClicked.schema

        #expect(actual == expected)
    }

    @Test("An event with no stored properties has an empty schema and encodes to an empty map")
    func empty() throws {
        let expectedSchema = EventSchema(name: "Crashed", version: 1, consentCategory: ConsentCategory("crash-reports"), properties: [])
        let expectedBytes: [UInt8] = [0xA0]

        let bytes = try CBOREncoder().encode(Crashed())
        _ = try CBORDecoder().decode(Crashed.self, from: expectedBytes)

        #expect(Crashed.schema == expectedSchema)
        #expect(bytes == expectedBytes)
    }

    @Test("The schema leaves out static and computed properties and a let with an initial value, and keeps observed ones and marks a var with an initial value as having a default")
    func schemaSkips() {
        let expected = [
            EventSchema.Property(name: "count", typeName: "Int", isOptional: false),
            EventSchema.Property(name: "tags", typeName: "[String]", isOptional: false),
            EventSchema.Property(name: "ratio", typeName: "Double", isOptional: true),
            EventSchema.Property(name: "wrapped", typeName: "Bool", isOptional: true),
            EventSchema.Property(name: "qualified", typeName: "Int8", isOptional: true),
            EventSchema.Property(name: "default", typeName: "UInt8", isOptional: false),
            EventSchema.Property(name: "encoder", typeName: "Int16", isOptional: false),
            EventSchema.Property(name: "decoder", typeName: "Int16", isOptional: false),
            EventSchema.Property(name: "map", typeName: "Int16", isOptional: false),
            EventSchema.Property(name: "first", typeName: "UInt16", isOptional: false),
            EventSchema.Property(name: "second", typeName: "UInt16", isOptional: false),
            EventSchema.Property(name: "assigned", typeName: "Bool", isOptional: false),
            EventSchema.Property(name: "observed", typeName: "Int32", isOptional: false, hasDefaultValue: true),
        ]

        let actual = Shapes.schema.properties

        #expect(actual == expected)
    }

    @Test("The event is a map with each stored property under its name, keys in CBOR's sorted order, each value in its own form")
    func encodesSorted() throws {
        // {"plan": "pro", "seats": 3}
        let expected: [UInt8] = [0xA2, 0x64, 0x70, 0x6C, 0x61, 0x6E, 0x63, 0x70, 0x72, 0x6F, 0x65, 0x73, 0x65, 0x61, 0x74, 0x73, 0x03]

        let actual = try CBOREncoder().encode(SignedUp(plan: "pro", seats: 3))

        #expect(actual == expected)
    }

    @Test("An optional property's nil is left out of the map")
    func nilLeftOut() throws {
        // {"plan": "pro"}
        let expected: [UInt8] = [0xA1, 0x64, 0x70, 0x6C, 0x61, 0x6E, 0x63, 0x70, 0x72, 0x6F]

        let actual = try CBOREncoder().encode(SignedUp(plan: "pro", seats: nil))

        #expect(actual == expected)
    }

    @Test("Each stored property is read back by its name, and an optional one from a missing key or a null as nil")
    func decodesByName() throws {
        let missing = CBOR.map([.textString("plan"): .textString("team")]).encode()
        let null = CBOR.map([.textString("seats"): .null, .textString("plan"): .textString("team")]).encode()
        let expectedPlan = "team"

        let actual = try [missing, null].map { try CBORDecoder().decode(SignedUp.self, from: $0) }

        #expect(actual.map(\.plan) == [expectedPlan, expectedPlan])
        #expect(actual.map(\.seats) == [nil, nil])
    }

    @Test("Properties named like the coding's parameters, or with backticks, still encode and decode themselves")
    func awkwardNames() throws {
        let value = Shapes(count: 1, tags: ["a"], ratio: 0.5, wrapped: true, qualified: -2, default: 9, encoder: 10, decoder: 11, map: 15, first: 12, second: 13, assigned: true, observed: 14)
        let bytes = try CBOREncoder().encode(value)

        let actual = try CBORDecoder().decode(Shapes.self, from: bytes)

        #expect(actual.count == 1)
        #expect(actual.tags == ["a"])
        #expect(actual.ratio == 0.5)
        #expect(actual.wrapped == true)
        #expect(actual.qualified == -2)
        #expect(actual.default == 9)
        #expect(actual.encoder == 10)
        #expect(actual.decoder == 11)
        #expect(actual.map == 15)
        #expect(actual.first == 12)
        #expect(actual.second == 13)
        #expect(actual.assigned)
        #expect(actual.observed == 14)
        #expect(actual.fixed == 7)
    }

    @Test("Bytes cut short of an event throw rather than read past the end")
    func truncated() throws {
        let bytes = try CBOREncoder().encode(SignedUp(plan: "pro", seats: 3))
        let expected = CBORError.unexpectedEnd(offset: 16)

        #expect(throws: expected) {
            _ = try CBORDecoder().decode(SignedUp.self, from: Array(bytes.dropLast()))
        }
    }

    @Test("A required property missing from the map throws keyNotFound naming it")
    func requiredMissing() {
        let bytes = CBOR.map([.textString("seats"): 2]).encode()
        let expectedKey = "plan"

        let error = #expect(throws: DecodingError.self) {
            _ = try CBORDecoder().decode(SignedUp.self, from: bytes)
        }

        guard case .keyNotFound(let key, _) = error else {
            Issue.record("Expected keyNotFound, got \(String(describing: error))")
            return
        }
        #expect(key.stringValue == expectedKey)
    }

    @Test("A generic event encodes its generic property")
    func generic() throws {
        let expected = EventSchema(name: "Box<String>", version: 1, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "value", typeName: "Value", isOptional: false),
        ])
        let bytes = try CBOREncoder().encode(Box(value: "lid"))

        let actual = try CBORDecoder().decode(Box<String>.self, from: bytes)

        #expect(actual.value == "lid")
        #expect(Box<String>.schema == expected)
    }

    @Test("A public event's generated members are public, as its conformances need")
    func published() throws {
        let bytes = try CBOREncoder().encode(Published(value: 5))

        let actual = try CBORDecoder().decode(Published.self, from: bytes)

        #expect(actual.value == 5)
        #expect(Published.name == "Published")
    }
}
