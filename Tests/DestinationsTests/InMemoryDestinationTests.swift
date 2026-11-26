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

    @Test("Below its capacity it keeps every record", arguments: [(capacity: 3, tracked: 2), (capacity: 3, tracked: 3)])
    func belowCapacity(capacity: Int, tracked: Int) async throws {
        let sut = try InMemoryDestination(capacity: capacity)
        let tracker = Tracker()
        let delivery = tracker.records.batch(strategy: .count(1)).deliver(to: sut)
        let expected = Array(1...tracked)

        for number in 1...tracked {
            tracker.track(Tapped(number: number))
        }
        await tracker.finish()
        try await delivery.execute()

        let actual = sut.events(of: Tapped.self).map(\.number)
        #expect(actual == expected)
    }

    @Test("One record past its capacity drops the oldest")
    func pastCapacity() async throws {
        let sut = try InMemoryDestination(capacity: 3)
        let tracker = Tracker()
        let delivery = tracker.records.batch(strategy: .count(1)).deliver(to: sut)
        let expectedRecords = [2, 3, 4]
        let expectedBatches = [[2], [3], [4]]

        for number in 1...4 {
            tracker.track(Tapped(number: number))
        }
        await tracker.finish()
        try await delivery.execute()

        let actualRecords = sut.records.compactMap { ($0.event as? Tapped)?.number }
        let actualBatches = sut.batches.map { $0.compactMap { ($0.event as? Tapped)?.number } }
        #expect(actualRecords == expectedRecords)
        #expect(actualBatches == expectedBatches)
    }

    @Test("Across batches it keeps the newest records, and the oldest kept batch holds only the newest of its records")
    func acrossBatches() async throws {
        let sut = try InMemoryDestination(capacity: 5)
        let tracker = Tracker()
        let delivery = tracker.records.batch(strategy: .count(3)).deliver(to: sut)
        let expectedRecords = [3, 4, 5, 6, 7]
        let expectedBatches = [[3], [4, 5, 6], [7]]

        for number in 1...7 {
            tracker.track(Tapped(number: number))
        }
        await tracker.finish()
        try await delivery.execute()

        let actualRecords = sut.records.compactMap { ($0.event as? Tapped)?.number }
        let actualBatches = sut.batches.map { $0.compactMap { ($0.event as? Tapped)?.number } }
        #expect(actualRecords == expectedRecords)
        #expect(actualBatches == expectedBatches)
    }

    @Test("A batch that drops several older batches whole and part of the next keeps the rest in order")
    func dropsSeveralBatches() async throws {
        let sut = try InMemoryDestination(capacity: 4)
        let location = SourceLocation(file: "A.swift", fileID: "M/A.swift", function: "f()", line: 1, column: 1)
        let received = [[1], [2], [3, 4, 5], [6, 7]].map { numbers in
            numbers.map { EventRecord(event: Tapped(number: $0), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location) }
        }
        let expectedBatches = [[4, 5], [6, 7]]

        for batch in received {
            await sut.receive(batch)
        }

        let actualBatches = sut.batches.map { $0.compactMap { ($0.event as? Tapped)?.number } }
        #expect(actualBatches == expectedBatches)
    }

    @Test("A batch larger than the capacity keeps only its newest records")
    func batchLargerThanCapacity() async throws {
        let sut = try InMemoryDestination(capacity: 2)
        let location = SourceLocation(file: "A.swift", fileID: "M/A.swift", function: "f()", line: 1, column: 1)
        let received = [[1], [2, 3, 4, 5]].map { numbers in
            numbers.map { EventRecord(event: Tapped(number: $0), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location) }
        }
        let expectedBatches = [[4, 5]]

        for batch in received {
            await sut.receive(batch)
        }

        let actualBatches = sut.batches.map { $0.compactMap { ($0.event as? Tapped)?.number } }
        #expect(actualBatches == expectedBatches)
    }

    @Test("The default capacity keeps the newest 1,000 records")
    func defaultCapacity() async {
        let sut = InMemoryDestination()
        let location = SourceLocation(file: "A.swift", fileID: "M/A.swift", function: "f()", line: 1, column: 1)
        let received = (1...1_001).map { EventRecord(event: Tapped(number: $0), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location) }
        let expectedDefault = 1_000
        let expected = Array(2...1_001)

        await sut.receive(received)

        let actual = sut.events(of: Tapped.self).map(\.number)
        #expect(InMemoryDestination.defaultCapacity == expectedDefault)
        #expect(actual == expected)
    }

    @Test("An unbounded destination keeps every record, and buffers every unread delivery")
    func unbounded() async throws {
        let sut = InMemoryDestination.unbounded()
        let location = SourceLocation(file: "A.swift", fileID: "M/A.swift", function: "f()", line: 1, column: 1)
        let received = (1...1_001).map { [EventRecord(event: Tapped(number: $0), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location)] }
        let expectedRecords = Array(1...1_001)
        let expectedFirstDelivery = [1]

        for batch in received {
            await sut.receive(batch)
        }

        let actualRecords = sut.events(of: Tapped.self).map(\.number)
        var deliveries = sut.deliveries.makeAsyncIterator()
        let first = try #require(await deliveries.next())
        let actualFirstDelivery = first.compactMap { ($0.event as? Tapped)?.number }
        #expect(actualRecords == expectedRecords)
        #expect(actualFirstDelivery == expectedFirstDelivery)
    }

    @Test("deliveries buffers the newest capacity batches while nobody reads, dropping the oldest")
    func deliveriesBounded() async throws {
        let sut = try InMemoryDestination(capacity: 2)
        let location = SourceLocation(file: "A.swift", fileID: "M/A.swift", function: "f()", line: 1, column: 1)
        let received = [[1], [2], [3]].map { numbers in
            numbers.map { EventRecord(event: Tapped(number: $0), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location) }
        }
        let expected = [[2], [3]]

        for batch in received {
            await sut.receive(batch)
        }

        var deliveries = sut.deliveries.makeAsyncIterator()
        let second = try #require(await deliveries.next())
        let third = try #require(await deliveries.next())
        let actual = [second, third].map { $0.compactMap { ($0.event as? Tapped)?.number } }
        #expect(actual == expected)
    }

    @Test("The initializer throws InvalidCapacity for a capacity below 1", arguments: [0, -1, Int.min])
    func invalidCapacity(capacity: Int) {
        #expect(throws: InvalidCapacity()) {
            _ = try InMemoryDestination(capacity: capacity)
        }
    }

    @Test("A destination keeps the newest capacity records, down to 1")
    func keeps() async throws {
        let sut = try InMemoryDestination(capacity: 1)
        let location = SourceLocation(file: "A.swift", fileID: "M/A.swift", function: "f()", line: 1, column: 1)
        let received = [1, 2].map { EventRecord(event: Tapped(number: $0), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location) }
        let expected = [Tapped(number: 2)]

        await sut.receive(received)

        let actual = sut.events(of: Tapped.self)
        #expect(actual == expected)
    }
}
