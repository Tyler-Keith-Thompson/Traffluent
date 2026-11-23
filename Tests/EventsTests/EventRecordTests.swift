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

    @Test("A record made with no source location has none")
    func noSourceLocation() {
        let actual = EventRecord(event: SignedUp(plan: "pro"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)

        #expect(actual.sourceLocation == nil)
    }

    @Test("A record's context is empty unless one is given")
    func defaultContext() {
        let location = Events.SourceLocation(file: "A/B.swift", fileID: "A/B.swift", function: "f()", line: 4, column: 2)

        let actual = EventRecord(event: SignedUp(plan: "pro"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location)

        #expect(actual.context[SessionKey.self] == nil)
    }

    final class Store: Acknowledger {
        func willDeliver(_ positions: [UInt64]) -> Set<UInt64> { [] }
        func acknowledge(_ positions: [UInt64]) {}
    }

    @Test("A record is not redelivered, and kept in memory only, unless it says otherwise")
    func defaultDelivery() {
        let location = Events.SourceLocation(file: "A/B.swift", fileID: "A/B.swift", function: "f()", line: 4, column: 2)

        let actual = EventRecord(event: SignedUp(plan: "pro"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location)

        #expect(!actual.isRedelivered)
        #expect(actual.deliveryTag == nil)
    }

    @Test("A record keeps the redelivery marker and delivery tag it is given")
    func delivery() throws {
        let location = Events.SourceLocation(file: "A/B.swift", fileID: "A/B.swift", function: "f()", line: 4, column: 2)
        let store = Store()
        let expectedPosition: UInt64 = 42

        let actual = EventRecord(event: SignedUp(plan: "pro"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location, isRedelivered: true, deliveryTag: DeliveryTag(acknowledger: store, position: expectedPosition))

        let tag = try #require(actual.deliveryTag)
        #expect(actual.isRedelivered)
        #expect(tag.position == expectedPosition)
        #expect(tag.acknowledger === store)
    }

    @Test("A record keeps the identifier it is given")
    func identifier() throws {
        let expected = try #require(UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F"))

        let actual = EventRecord(id: expected, event: SignedUp(plan: "pro"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)

        #expect(actual.id == expected)
    }

    @Test("Two records made without an identifier get different random (version 4) ones, even of the same event")
    func distinctIdentifiers() {
        let location = Events.SourceLocation(file: "A/B.swift", fileID: "A/B.swift", function: "f()", line: 4, column: 2)
        let expectedVersion: UInt8 = 4

        let first = EventRecord(event: SignedUp(plan: "pro"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location)
        let second = EventRecord(event: SignedUp(plan: "pro"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location)

        #expect(first.id != second.id)
        #expect(first.id.uuid.6 >> 4 == expectedVersion)
        #expect(second.id.uuid.6 >> 4 == expectedVersion)
    }
}
