import DestinationTesting
import Destinations
import Events
import Foundation
import Testing
import Trackers

@Suite("InMemoryDestination", .timeLimit(.minutes(1)))
struct InMemoryDestinationTests {
    struct Tapped: Event, Equatable {
        var number: Int
    }

    struct Viewed: Event, Equatable {
        var screen: String
    }

    @Test("A new destination has received nothing")
    func empty() {
        let sut = InMemoryDestination()

        #expect(sut.batches.isEmpty)
        #expect(sut.records.isEmpty)
        #expect(sut.events(of: Tapped.self).isEmpty)
    }

    @Test("It keeps every batch, and every record across batches, in the order received")
    func order() async throws {
        let sut = InMemoryDestination()
        let tracker = Tracker()
        let delivery = tracker.records.batch(strategy: .count(2)).deliver(to: sut)
        let expectedBatches = [[1, 2], [3]]
        let expectedRecords = [1, 2, 3]

        for number in 1...3 {
            tracker.track(Tapped(number: number))
        }
        await tracker.finish()
        try await delivery.execute()

        let actualBatches = sut.batches.map { $0.compactMap { ($0.event as? Tapped)?.number } }
        let actualRecords = sut.records.compactMap { ($0.event as? Tapped)?.number }
        #expect(actualBatches == expectedBatches)
        #expect(actualRecords == expectedRecords)
    }

    @Test("events(of:) reads the events of one type, as that type, and leaves out the rest")
    func typed() async throws {
        let sut = InMemoryDestination()
        let tracker = Tracker()
        let delivery = tracker.records.batch().deliver(to: sut)
        let expectedTaps = [Tapped(number: 1), Tapped(number: 2)]
        let expectedViews = [Viewed(screen: "Home")]

        tracker.track(Tapped(number: 1))
        tracker.track(Viewed(screen: "Home"))
        tracker.track(Tapped(number: 2))
        await tracker.finish()
        try await delivery.execute()

        let actualTaps = sut.events(of: Tapped.self)
        let actualViews = sut.events(of: Viewed.self)
        #expect(actualTaps == expectedTaps)
        #expect(actualViews == expectedViews)
    }

    @Test("Copies share one log")
    func copiesShare() async {
        let sut = InMemoryDestination()
        let copy = sut
        let record = EventRecord(
            event: Tapped(number: 1), timestamp: Date(timeIntervalSince1970: 0),
            sourceLocation: SourceLocation(file: "A.swift", fileID: "M/A.swift", function: "f()", line: 1, column: 1))
        let expected = [Tapped(number: 1)]

        await copy.receive([record])

        let actual = sut.events(of: Tapped.self)
        #expect(actual == expected)
    }

    @Test("deliveries announces each batch as it is received")
    func deliveries() async throws {
        let sut = InMemoryDestination()
        let tracker = Tracker()
        let delivery = tracker.records.batch(strategy: .count(1)).deliver(to: sut)
        let expected = [Tapped(number: 1)]

        let running = Task { try await delivery.execute() }
        tracker.track(Tapped(number: 1))
        var deliveries = sut.deliveries.makeAsyncIterator()
        let batch = try #require(await deliveries.next())
        await tracker.finish()
        try await running.value

        let actual = batch.compactMap { $0.event as? Tapped }
        #expect(actual == expected)
    }

    @Test("Events tracked from many tasks at once, read while they arrive, are each kept exactly once")
    func concurrent() async throws {
        let sut = InMemoryDestination()
        let tracker = Tracker()
        let delivery = tracker.records.batch(strategy: .count(7)).deliver(to: sut)
        let expected = Array(1...500)

        let running = Task { try await delivery.execute() }
        let reader = Task {
            var reads = 0
            while !Task.isCancelled {
                _ = sut.records.count
                reads += 1
                await Task.yield()
            }
            return reads
        }
        await withDiscardingTaskGroup { group in
            for number in expected {
                group.addTask { tracker.track(Tapped(number: number)) }
            }
        }
        await tracker.finish()
        try await running.value
        reader.cancel()
        _ = await reader.value

        let actual = sut.events(of: Tapped.self).map(\.number).sorted()
        #expect(actual == expected)
    }
}
