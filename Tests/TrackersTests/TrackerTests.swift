import Afluent
import Destinations
import Events
import Foundation
import Synchronization
import Testing
import Trackers

@Suite("Tracker", .timeLimit(.minutes(1)))
struct TrackerTests {
    struct Tapped: Event {
        var number: Int
    }

    /// Hands out 1970 plus one second, plus two, and so on: a later date each call.
    final class Ticker: Sendable {
        let calls = Mutex(0)

        func now() -> Date {
            calls.withLock {
                $0 += 1
                return Date(timeIntervalSince1970: Double($0))
            }
        }
    }

    /// Never flushes; sends `started` each time a delivery starts it, so a test knows the
    /// delivery is reading.
    struct StartGate<Element>: BatchStrategy {
        let started: SingleValueSubject<Void>

        func run(_ flusher: BatchFlusher) async throws {
            try? started.send()
        }
    }

    /// Counts its runs: the first throws, a later one sends `retried`.
    struct FailsOnce<Element>: BatchStrategy {
        struct Broken: Error {}

        final class Runs: Sendable {
            let count = Mutex(0)
        }

        let runs = Runs()
        let retried: SingleValueSubject<Void>

        func run(_ flusher: BatchFlusher) async throws {
            let run = runs.count.withLock {
                $0 += 1
                return $0
            }
            guard run > 1 else { throw Broken() }
            try? retried.send()
        }
    }

    @Test("The records are the tracked events, in the order tracked, ending at finish")
    func records() async {
        let sut = Tracker()
        let expected = [1, 2, 3]

        sut.track(Tapped(number: 1))
        sut.track(Tapped(number: 2))
        sut.track(Tapped(number: 3))
        await sut.finish()

        var actual: [Int] = []
        for await record in sut.records {
            actual.append((record.event as? Tapped)?.number ?? -1)
        }
        #expect(actual == expected)
    }

    @Test("A record carries its event, with the event's type and value")
    func event() async throws {
        let sut = Tracker()
        let expectedName = "Tapped"
        let expectedNumber = 9

        sut.track(Tapped(number: expectedNumber))
        await sut.finish()

        var records = sut.records.makeAsyncIterator()
        let record = try #require(await records.next())
        let event = try #require(record.event as? Tapped)
        #expect(record.name == expectedName)
        #expect(event.number == expectedNumber)
    }

    @Test("An event tracked after finish is dropped")
    func trackAfterFinish() async {
        let sut = Tracker()
        let expected = [1]

        sut.track(Tapped(number: 1))
        await sut.finish()
        sut.track(Tapped(number: 2))

        var actual: [Int] = []
        for await record in sut.records {
            actual.append((record.event as? Tapped)?.number ?? -1)
        }
        #expect(actual == expected)
    }

    @Test("Copies of a tracker share one stream of records")
    func copiesShare() async {
        let sut = Tracker()
        let copy = sut
        let expected = [1, 2]

        sut.track(Tapped(number: 1))
        copy.track(Tapped(number: 2))
        await copy.finish()

        var actual: [Int] = []
        for await record in sut.records {
            actual.append((record.event as? Tapped)?.number ?? -1)
        }
        #expect(actual == expected)
    }

    @Test("A read after an earlier read returned continues with the next record")
    func readAgain() async {
        let sut = Tracker()
        let expectedFirst = 1
        let expectedSecond = 2
        sut.track(Tapped(number: 1))
        sut.track(Tapped(number: 2))

        var first = sut.records.makeAsyncIterator()
        let actualFirst = await first.next()
        var second = sut.records.makeAsyncIterator()
        let actualSecond = await second.next()

        #expect((actualFirst?.event as? Tapped)?.number == expectedFirst)
        #expect((actualSecond?.event as? Tapped)?.number == expectedSecond)
    }

    @Test("A read on a task already cancelled returns nil and keeps the records for the next read")
    func readCancelled() async {
        let sut = Tracker()
        let expected = [1]
        sut.track(Tapped(number: 1))

        let actualCancelled = await withTaskGroup(of: EventRecord?.self) { group in
            // A task added to a cancelled group starts cancelled.
            group.cancelAll()
            group.addTask {
                var records = sut.records.makeAsyncIterator()
                return await records.next()
            }
            return await group.next() ?? nil
        }
        await sut.finish()

        var actual: [Int] = []
        for await record in sut.records {
            actual.append((record.event as? Tapped)?.number ?? -1)
        }
        #expect(actualCancelled == nil)
        #expect(actual == expected)
    }

    @Test("A no-op tracker's records are empty")
    func noOpRecords() async {
        let sut = Tracker.noOp
        let expected: [Int] = []

        sut.track(Tapped(number: 1))
        await sut.finish()

        var actual: [Int] = []
        for await record in sut.records {
            actual.append((record.event as? Tapped)?.number ?? -1)
        }
        #expect(actual == expected)
    }

    @Test("Each record is stamped with the wall-clock time `now` gives when its event is tracked")
    func timestamps() async {
        let ticker = Ticker()
        let sut = Tracker(now: { ticker.now() })
        let expected = [Date(timeIntervalSince1970: 1), Date(timeIntervalSince1970: 2), Date(timeIntervalSince1970: 3)]

        sut.track(Tapped(number: 1))
        sut.track(Tapped(number: 2))
        sut.track(Tapped(number: 3))
        await sut.finish()

        var actual: [Date] = []
        for await record in sut.records {
            actual.append(record.timestamp)
        }
        #expect(actual == expected)
    }

    @Test("Each tracked event's record has an identifier of its own, given when tracked, which the enrichers see and the worker keeps")
    func identifiers() async {
        let seen = Mutex<[UUID]>([])
        let watching = Enricher(records: { record in
            seen.withLock { $0.append(record.id) }
            return []
        })
        let sut = Tracker(enrichers: [watching])
        let expectedCount = 3

        sut.track(Tapped(number: 1))
        sut.track(Tapped(number: 1))
        sut.track(Tapped(number: 1))
        await sut.finish()

        var actual: [UUID] = []
        for await record in sut.records {
            actual.append(record.id)
        }
        let expected = seen.withLock { $0 }
        #expect(actual == expected)
        #expect(Set(actual).count == expectedCount)
    }

    @Test("By default each record is stamped with the system's current time")
    func defaultTimestamp() async throws {
        let sut = Tracker()
        let earliest = Date.now

        sut.track(Tapped(number: 1))
        let latest = Date.now
        await sut.finish()

        var records = sut.records.makeAsyncIterator()
        let actual = try #require(await records.next()).timestamp
        #expect(actual >= earliest)
        #expect(actual <= latest)
    }

    @Test("Tracking captures the caller's file, file ID, module, function, line and column")
    func capturedSourceLocation() async throws {
        let sut = Tracker()
        // In the Swift 6 language mode `#file` is the file ID.
        let expectedFile = "TrackersTests/TrackerTests.swift"
        let expectedFileID = "TrackersTests/TrackerTests.swift"
        let expectedModule = "TrackersTests"
        let expectedFunction = "capturedSourceLocation()"
        // `#column` as a default argument is the column of the call's opening parenthesis.
        let expectedColumn = 18
        let expectedLine = #line + 2

        sut.track(Tapped(number: 1))
        await sut.finish()

        var records = sut.records.makeAsyncIterator()
        let actual = try #require(await records.next()?.sourceLocation)
        #expect(actual.file == expectedFile)
        #expect(actual.fileID == expectedFileID)
        #expect(actual.moduleName == expectedModule)
        #expect(actual.function == expectedFunction)
        #expect(actual.line == expectedLine)
        #expect(actual.column == expectedColumn)
    }

    @Test("A source location passed explicitly is recorded field for field")
    func explicitSourceLocation() async throws {
        let sut = Tracker()
        let expected = Events.SourceLocation(file: "/src/App/Cart.swift", fileID: "App/Cart.swift", function: "pay()", line: 41, column: 7)

        sut.track(Tapped(number: 1), file: "/src/App/Cart.swift", fileID: "App/Cart.swift", function: "pay()", line: 41, column: 7)
        await sut.finish()

        var records = sut.records.makeAsyncIterator()
        let actual = try #require(await records.next()).sourceLocation
        #expect(actual == expected)
    }

    @Test("A tracker's records reveal their events' sensitive values")
    func revealsSensitiveValues() async throws {
        struct SignedUp: Event {
            var email: Sensitive<String>
        }
        let sut = Tracker()
        let expected = "ada@example.com"

        sut.track(SignedUp(email: Sensitive("ada@example.com")))
        await sut.finish()

        var records = sut.records.makeAsyncIterator()
        let record = try #require(await records.next())
        let event = try #require(record.event as? SignedUp)
        #expect(record.reveal(event.email) == expected)
    }

    @Test("Events tracked before a delivery starts are delivered")
    func trackedBeforeDelivery() async throws {
        let recorder = InMemoryDestination()
        let sut = Tracker()
        let expected = [1, 2]

        sut.track(Tapped(number: 1))
        sut.track(Tapped(number: 2))
        await sut.finish()
        try await sut.records.batch(strategy: .count(5)).deliver(to: recorder).execute()

        let actual = recorder.events(of: Tapped.self).map(\.number)
        #expect(actual == expected)
    }

    @Test("After a cancelled delivery, the next delivers the events tracked since")
    func deliverAgainAfterCancel() async throws {
        let started = SingleValueSubject<Void>()
        let recorder = InMemoryDestination()
        let sut = Tracker()
        let expected = [2, 3]
        let first = sut.records.batch(strategy: .either(.count(5), StartGate(started: started))).deliver(to: recorder)
        let running = Task { try await first.execute() }
        try await started.execute()
        running.cancel()
        _ = await running.result

        sut.track(Tapped(number: 2))
        sut.track(Tapped(number: 3))
        await sut.finish()
        try await sut.records.batch(strategy: .count(5)).deliver(to: recorder).execute()

        let actual = recorder.events(of: Tapped.self).map(\.number)
        #expect(actual == expected)
    }

    @Test("Retrying a delivery whose strategy failed reads again and delivers")
    func retryAfterFailure() async throws {
        let retried = SingleValueSubject<Void>()
        let recorder = InMemoryDestination()
        let sut = Tracker()
        let expected = [1]
        let work = sut.records.batch(strategy: .either(.count(5), FailsOnce(retried: retried))).deliver(to: recorder).retry(1)
        let running = Task { try await work.execute() }
        try await retried.execute()

        sut.track(Tapped(number: 1))
        await sut.finish()
        try await running.value

        let actual = recorder.events(of: Tapped.self).map(\.number)
        #expect(actual == expected)
    }
}
