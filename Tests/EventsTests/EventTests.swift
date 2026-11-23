import Events
import Testing

@Suite("Event")
struct EventTests {
    struct SignedUp: Event {
        var plan: String
    }

    struct Renamed: Event {
        static let name = "renamed_event"
    }

    @Test("An event's name defaults to its type's name")
    func defaultName() {
        let expected = "SignedUp"

        let actual = SignedUp.name

        #expect(actual == expected)
    }

    @Test("An event type can give its own name")
    func customName() {
        let expected = "renamed_event"

        let actual = Renamed.name

        #expect(actual == expected)
    }
}

@Suite("Event: constraints")
struct EventConstraintTests {
    struct Viewed: Event {
        var screen: String
    }

    @Test("A schema property keeps the keywords it is given, and has none by default")
    func propertyKeywords() {
        let expected: [ValidationKeyword] = [.minLength(1), .maxLength(8)]

        let actual = EventSchema.Property(name: "query", typeName: "String", isOptional: false, keywords: expected)
        let plain = EventSchema.Property(name: "query", typeName: "String", isOptional: false)

        #expect(actual.keywords == expected)
        #expect(plain.keywords.isEmpty)
    }

    @Test("An event that declares no constraints has no violation")
    func noViolationByDefault() {
        let sut = Viewed(screen: "")

        let actual = sut.constraintViolation()

        #expect(actual == nil)
    }

    @Test("A schema property has no keywords unless it is given some")
    func noKeywordsByDefault() {
        let sut = EventSchema.Property(name: "screen", typeName: "String", isOptional: false)
        let expected: [ValidationKeyword] = []

        let actual = sut.keywords

        #expect(actual == expected)
    }
}
