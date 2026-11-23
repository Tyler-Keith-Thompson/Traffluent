// What @Event generates, compiled by the real compiler and run: names, consent categories,
// schemas and the binary encoding, against hand-worked bytes.

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
    struct Box<Value: BinaryCodable & Sendable> {
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
        let expected = EventSchema(name: "SignedUp", version: 1, properties: [
            EventSchema.Property(name: "plan", typeName: "String", isOptional: false),
            EventSchema.Property(name: "seats", typeName: "Int", isOptional: true),
        ])

        let actual = SignedUp.schema

        #expect(actual == expected)
    }

    @Test("The schema takes the macro's name and version")
    func schemaNameAndVersion() {
        let expected = EventSchema(name: "ad_clicked", version: 3, properties: [
            EventSchema.Property(name: "campaign", typeName: "String", isOptional: false),
        ])

        let actual = AdClicked.schema

        #expect(actual == expected)
    }

    @Test("An event with no stored properties has an empty schema and encodes to no bytes")
    func empty() throws {
        let expectedSchema = EventSchema(name: "Crashed", version: 1, properties: [])
        let expectedBytes: [UInt8] = []
        var encoder = BinaryEncoder()
        var decoder = BinaryDecoder([])

        Crashed().encode(to: &encoder)
        _ = try Crashed(from: &decoder)

        #expect(Crashed.schema == expectedSchema)
        #expect(encoder.bytes == expectedBytes)
        #expect(decoder.isAtEnd)
    }

    @Test("The schema leaves out static and computed properties and a let with an initial value, and keeps observed ones")
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
            EventSchema.Property(name: "first", typeName: "UInt16", isOptional: false),
            EventSchema.Property(name: "second", typeName: "UInt16", isOptional: false),
            EventSchema.Property(name: "assigned", typeName: "Bool", isOptional: false),
            EventSchema.Property(name: "observed", typeName: "Int32", isOptional: false),
        ]

        let actual = Shapes.schema.properties

        #expect(actual == expected)
    }

    @Test("Each stored property is written in declaration order, in its own binary form")
    func encodesInOrder() {
        var reference = BinaryEncoder()
        reference.encode("pro")
        reference.encode(Int?.some(3))
        let expected = reference.bytes
        var sut = BinaryEncoder()

        SignedUp(plan: "pro", seats: 3).encode(to: &sut)

        #expect(sut.bytes == expected)
    }

    @Test("Each stored property is read back in declaration order")
    func decodesInOrder() throws {
        var encoder = BinaryEncoder()
        encoder.encode("team")
        encoder.encode(Int?.none)
        var decoder = BinaryDecoder(encoder.bytes)

        let actual = try SignedUp(from: &decoder)

        #expect(actual.plan == "team")
        #expect(actual.seats == nil)
        #expect(decoder.isAtEnd)
    }

    @Test("Properties named like the encoding's parameters, or with backticks, still encode and decode themselves")
    func awkwardNames() throws {
        let value = Shapes(count: 1, tags: ["a"], ratio: 0.5, wrapped: true, qualified: -2, default: 9, encoder: 10, decoder: 11, first: 12, second: 13, assigned: true, observed: 14)
        var encoder = BinaryEncoder()
        value.encode(to: &encoder)
        var decoder = BinaryDecoder(encoder.bytes)

        let actual = try Shapes(from: &decoder)

        #expect(actual.count == 1)
        #expect(actual.tags == ["a"])
        #expect(actual.ratio == 0.5)
        #expect(actual.wrapped == true)
        #expect(actual.qualified == -2)
        #expect(actual.default == 9)
        #expect(actual.encoder == 10)
        #expect(actual.decoder == 11)
        #expect(actual.first == 12)
        #expect(actual.second == 13)
        #expect(actual.assigned)
        #expect(actual.observed == 14)
        #expect(actual.fixed == 7)
        #expect(decoder.isAtEnd)
    }

    @Test("Bytes cut short of an event throw rather than read past the end")
    func truncated() {
        var encoder = BinaryEncoder()
        encoder.encode("pro")
        var decoder = BinaryDecoder(encoder.bytes)

        #expect(throws: BinaryDecodingError.endOfData) {
            _ = try SignedUp(from: &decoder)
        }
    }

    @Test("A generic event encodes its generic property")
    func generic() throws {
        let expected = EventSchema(name: "Box<String>", version: 1, properties: [
            EventSchema.Property(name: "value", typeName: "Value", isOptional: false),
        ])
        var encoder = BinaryEncoder()
        Box(value: "lid").encode(to: &encoder)
        var decoder = BinaryDecoder(encoder.bytes)

        let actual = try Box<String>(from: &decoder)

        #expect(actual.value == "lid")
        #expect(Box<String>.schema == expected)
    }

    @Test("A public event's generated members are public, as its conformances need")
    func published() throws {
        var encoder = BinaryEncoder()
        Published(value: 5).encode(to: &encoder)
        var decoder = BinaryDecoder(encoder.bytes)

        let actual = try Published(from: &decoder)

        #expect(actual.value == 5)
        #expect(Published.name == "Published")
    }
}
