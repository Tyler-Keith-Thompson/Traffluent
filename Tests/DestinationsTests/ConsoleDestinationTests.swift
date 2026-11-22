import Destinations
import Events
import Testing

@Suite("ConsoleDestination")
struct ConsoleDestinationTests {
    struct SignedUp: Event {
        var plan: String
    }

    @Test("The console line is the event's name, a space, then the value")
    func line() {
        let sut = ConsoleDestination()
        let expected = #"SignedUp SignedUp(plan: "pro")"#

        let actual = sut.line(for: SignedUp(plan: "pro"))

        #expect(actual == expected)
    }
}
