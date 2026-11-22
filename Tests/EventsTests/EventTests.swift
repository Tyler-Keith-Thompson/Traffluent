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
