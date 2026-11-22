import Destinations
import Events
import Foundation
import Testing

@Suite("ConsoleDestination")
struct ConsoleDestinationTests {
    struct SignedUp: Event {
        var plan: String
    }

    @Test("The console line is the event's name, a space, then the value")
    func line() {
        let location = Events.SourceLocation(file: "A/B.swift", fileID: "A/B.swift", function: "f()", line: 1, column: 1)
        let record = EventRecord(event: SignedUp(plan: "pro"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location)
        let sut = ConsoleDestination()
        let expected = #"SignedUp SignedUp(plan: "pro")"#

        let actual = sut.line(for: record)

        #expect(actual == expected)
    }
}
