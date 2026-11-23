import Destinations
import Events
import Foundation
import Testing
import Trackers

@Suite("droppingCallSite()", .timeLimit(.minutes(1)))
struct DroppingCallSiteTests {
    struct Tapped: Event {
        var number: Int
    }

    @Test("By default a destination receives each record's call site")
    func keptByDefault() async throws {
        let sut = InMemoryDestination()
        let tracker = Tracker()
        let expected = Events.SourceLocation(file: "App/Cart.swift", fileID: "App/Cart.swift", function: "pay()", line: 41, column: 7)

        tracker.track(Tapped(number: 1), file: "App/Cart.swift", fileID: "App/Cart.swift", function: "pay()", line: 41, column: 7)
        await tracker.finish()
        try await tracker.records.batch(strategy: .count(1)).deliver(to: sut).execute()

        let actual = try #require(sut.records.first)
        #expect(actual.sourceLocation == expected)
    }

    @Test("A destination dropping call sites receives records with none, and everything else as tracked")
    func dropped() async throws {
        let recorder = InMemoryDestination()
        let tracker = Tracker(now: { Date(timeIntervalSince1970: 9) })
        let sut = recorder.droppingCallSite()
        let expectedTimestamp = Date(timeIntervalSince1970: 9)
        let expectedNumbers = [1, 2]

        tracker.track(Tapped(number: 1))
        tracker.track(Tapped(number: 2))
        await tracker.finish()
        try await tracker.records.batch(strategy: .count(2)).deliver(to: sut).execute()

        let actual = recorder.records
        #expect(actual.map(\.sourceLocation) == [nil, nil])
        #expect(actual.compactMap { ($0.event as? Tapped)?.number } == expectedNumbers)
        #expect(actual.map(\.timestamp) == [expectedTimestamp, expectedTimestamp])
        #expect(actual.map(\.name) == ["Tapped", "Tapped"])
    }

    @Test("Dropping one destination's call sites leaves the other destinations' as tracked")
    func otherDestinationsKeepIt() async throws {
        let dropping = InMemoryDestination()
        let keeping = InMemoryDestination()
        let tracker = Tracker()

        tracker.track(Tapped(number: 1))
        await tracker.finish()
        try await tracker.records.batch(strategy: .count(1)).deliver(to: dropping.droppingCallSite(), keeping).execute()

        #expect(try #require(dropping.records.first).sourceLocation == nil)
        #expect(try #require(keeping.records.first).sourceLocation != nil)
    }
}
