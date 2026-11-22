import Events
import Foundation
import Instrumentation
import Testing

@Suite("EventRecord")
struct EventRecordTests {
    struct SignedUp: Event {
        var plan: String
    }

    struct Renamed: Event {
        static let name = "renamed_event"
    }

    @Test("A record's name is its event type's name")
    func name() {
        let location = Events.SourceLocation(file: "A/B.swift", fileID: "A/B.swift", function: "f()", line: 1, column: 1)
        let sut = EventRecord(event: Renamed(), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location)
        let expected = "renamed_event"

        let actual = sut.name

        #expect(actual == expected)
    }

    @Test("A record keeps its event, timestamp and source location as given")
    func initializer() throws {
        let expectedTimestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let expectedLocation = Events.SourceLocation(file: "A/B.swift", fileID: "A/B.swift", function: "f()", line: 4, column: 2)
        let expectedPlan = "pro"

        let actual = EventRecord(event: SignedUp(plan: expectedPlan), timestamp: expectedTimestamp, sourceLocation: expectedLocation)

        let event = try #require(actual.event as? SignedUp)
        #expect(event.plan == expectedPlan)
        #expect(actual.timestamp == expectedTimestamp)
        #expect(actual.sourceLocation == expectedLocation)
    }

    enum SessionKey: ServiceContextKey {
        typealias Value = String
    }

    @Test("A record keeps the context it is given")
    func context() {
        let location = Events.SourceLocation(file: "A/B.swift", fileID: "A/B.swift", function: "f()", line: 4, column: 2)
        var context = ServiceContext.topLevel
        context[SessionKey.self] = "s-1"
        let expected = "s-1"

        let actual = EventRecord(event: SignedUp(plan: "pro"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location, context: context)

        #expect(actual.context[SessionKey.self] == expected)
    }

    @Test("A record's context is empty unless one is given")
    func defaultContext() {
        let location = Events.SourceLocation(file: "A/B.swift", fileID: "A/B.swift", function: "f()", line: 4, column: 2)

        let actual = EventRecord(event: SignedUp(plan: "pro"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location)

        #expect(actual.context[SessionKey.self] == nil)
    }
}
