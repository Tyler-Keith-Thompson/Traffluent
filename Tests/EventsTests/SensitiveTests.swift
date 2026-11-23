import Events
import Foundation
import Testing

@Suite("Sensitive")
struct SensitiveTests {
    struct SignedUp: Event {
        var plan: String
        var email: Sensitive<String>
    }

    @Test("Describing a sensitive value shows <redacted>, never the value")
    func description() {
        let sut = Sensitive("ada@example.com")
        let expected = "<redacted>"

        let actual = "\(sut)"

        #expect(actual == expected)
    }

    @Test("Debug-describing a sensitive value shows Sensitive(<redacted>), never the value")
    func debugDescription() {
        let sut = Sensitive("ada@example.com")
        let expected = "Sensitive(<redacted>)"

        let actual = String(reflecting: sut)

        #expect(actual == expected)
    }

    @Test("Describing an event shows its other properties and hides the sensitive one")
    func eventDescription() {
        let sut = SignedUp(plan: "pro", email: Sensitive("ada@example.com"))
        let hidden = "ada@example.com"

        let actual = String(describing: sut)

        #expect(actual.contains("pro"))
        #expect(actual.contains("Sensitive(<redacted>)"))
        #expect(!actual.contains(hidden))
    }

    @Test("Dumping an event never reaches the sensitive value")
    func dumped() {
        let sut = SignedUp(plan: "pro", email: Sensitive("ada@example.com"))
        let hidden = "ada@example.com"
        var actual = ""

        dump(sut, to: &actual)

        #expect(!actual.contains(hidden))
    }

    @Test("A sensitive value's mirror has no children")
    func mirror() {
        let sut = Sensitive(42)

        let actual = Mirror(reflecting: sut).children.count

        #expect(actual == 0)
    }

    @Test("A record made with the public initializer doesn't reveal its sensitive values")
    func publicRecordRedacts() {
        let event = SignedUp(plan: "pro", email: Sensitive("ada@example.com"))
        let sut = EventRecord(event: event, timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)

        let actual = sut.reveal(event.email)

        #expect(actual == nil)
        #expect(!sut.revealsSensitiveValues)
    }
}
