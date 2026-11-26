import Afluent
import Destinations
import Events
import Testing
import Trackers

@Suite("Tracker: one reader at a time", .timeLimit(.minutes(1)))
struct TrackerReadTurnTests {
    struct Tapped: Event {
        var number: Int
    }

    @Test("A second reader that starts while the first waits gets none of the first's records, and once the first's iterator is released reads on in order")
    func secondReaderWaitsForRelease() async throws {
        let sut = Tracker()
        let firstHoldsTurn = SingleValueSubject<Void>()
        let secondAboutToRead = SingleValueSubject<Void>()
        let expectedFirst = [0, 1, 2, 3]
        let expectedSecond = [4, 5]
        let first = Task {
            var records = sut.records.makeAsyncIterator()
            var numbers: [Int] = []
            // The first read takes the turn, which the iterator keeps until this task releases it.
            if let record = await records.next() { numbers.append((record.event as? Tapped)?.number ?? -1) }
            try? firstHoldsTurn.send()
            for _ in 1 ... 3 {
                guard let record = await records.next() else { break }
                numbers.append((record.event as? Tapped)?.number ?? -1)
            }
            return numbers
        }
        sut.track(Tapped(number: 0))
        try await firstHoldsTurn.execute()
        let second = Task {
            var numbers: [Int] = []
            try? secondAboutToRead.send()
            for await record in sut.records {
                numbers.append((record.event as? Tapped)?.number ?? -1)
            }
            return numbers
        }
        try await secondAboutToRead.execute()

        sut.track(Tapped(number: 1))
        sut.track(Tapped(number: 2))
        sut.track(Tapped(number: 3))
        let actualFirst = await first.value
        sut.track(Tapped(number: 4))
        sut.track(Tapped(number: 5))
        await sut.finish()
        let actualSecond = await second.value

        #expect(actualFirst == expectedFirst)
        #expect(actualSecond == expectedSecond)
    }

    @Test("Once the first reader's iteration ends, a waiting reader reads on in order, though the first's iterator is still held")
    func secondReaderWaitsForEnd() async throws {
        let sut = Tracker()
        // Its job ignores the cancelled task awaiting it, so that task holds its iterator until
        // the test lets it go.
        let holder = SerialTaskQueue()
        let firstHoldsTurn = SingleValueSubject<Void>()
        let firstEnded = SingleValueSubject<Void>()
        let releaseFirst = SingleValueSubject<Void>()
        let expectedFirstEnd: Int? = nil
        let expectedSecond = [1, 2]
        let first = Task {
            var records = sut.records.makeAsyncIterator()
            _ = await records.next()
            try? firstHoldsTurn.send()
            // Cancelled while it waits: the iteration's end.
            let end = await records.next()
            try? firstEnded.send()
            try? await holder.enqueue { try? await releaseFirst.execute() }
            withExtendedLifetime(records) {}
            return (end?.event as? Tapped)?.number
        }
        sut.track(Tapped(number: 0))
        try await firstHoldsTurn.execute()
        let second = Task {
            var numbers: [Int] = []
            var records = sut.records.makeAsyncIterator()
            for _ in 1 ... 2 {
                guard let record = await records.next() else { break }
                numbers.append((record.event as? Tapped)?.number ?? -1)
            }
            return numbers
        }

        first.cancel()
        try await firstEnded.execute()
        sut.track(Tapped(number: 1))
        sut.track(Tapped(number: 2))
        let actualSecond = await second.value
        try releaseFirst.send()
        let actualFirstEnd = await first.value
        await sut.finish()

        #expect(actualFirstEnd == expectedFirstEnd)
        #expect(actualSecond == expectedSecond)
    }

    @Test("A delivery started as soon as a cancelled one's execute() returns delivers what is tracked next")
    func restartAfterCancel() async throws {
        let sut = Tracker()
        let firstRead = SingleValueSubject<Void>()
        let recorder = InMemoryDestination()
        let expected = [1]
        let cancelled = sut.records
            .handleEvents(receiveOutput: { _ in try? firstRead.send() })
            .batch(strategy: .count(5))
            .deliver(to: InMemoryDestination())
        let running = Task { try await cancelled.execute() }
        sut.track(Tapped(number: 0))
        // The cancelled delivery has read a record, so it holds the turn as it is cancelled.
        try await firstRead.execute()
        running.cancel()
        _ = await running.result

        let restarted = Task { try await sut.records.batch(strategy: .count(1)).deliver(to: recorder).execute() }
        sut.track(Tapped(number: 1))
        await sut.finish()
        try await restarted.value

        let actual = recorder.events(of: Tapped.self).map(\.number)
        #expect(actual == expected)
    }

    @Test("A waiting reader whose task is cancelled returns nil, and the reader holding the turn keeps every record")
    func waitingReaderCancelled() async throws {
        let sut = Tracker()
        let firstHoldsTurn = SingleValueSubject<Void>()
        let secondAboutToRead = SingleValueSubject<Void>()
        let expectedFirst = [0, 1, 2]
        let expectedSecond: Int? = nil
        let first = Task {
            var records = sut.records.makeAsyncIterator()
            var numbers: [Int] = []
            if let record = await records.next() { numbers.append((record.event as? Tapped)?.number ?? -1) }
            try? firstHoldsTurn.send()
            for _ in 1 ... 2 {
                guard let record = await records.next() else { break }
                numbers.append((record.event as? Tapped)?.number ?? -1)
            }
            return numbers
        }
        sut.track(Tapped(number: 0))
        try await firstHoldsTurn.execute()
        let second = Task {
            var records = sut.records.makeAsyncIterator()
            try? secondAboutToRead.send()
            let record = await records.next()
            return (record?.event as? Tapped)?.number
        }
        try await secondAboutToRead.execute()

        second.cancel()
        let actualSecond = await second.value
        sut.track(Tapped(number: 1))
        sut.track(Tapped(number: 2))
        let actualFirst = await first.value
        await sut.finish()

        #expect(actualSecond == expectedSecond)
        #expect(actualFirst == expectedFirst)
    }

    @Test("A reader whose task is already cancelled as another holds the turn returns nil rather than wait")
    func cancelledReaderDoesNotWait() async throws {
        let sut = Tracker()
        let firstHoldsTurn = SingleValueSubject<Void>()
        let expectedFirst = [0, 1]
        let expectedSecond: Int? = nil
        let first = Task {
            var records = sut.records.makeAsyncIterator()
            var numbers: [Int] = []
            if let record = await records.next() { numbers.append((record.event as? Tapped)?.number ?? -1) }
            try? firstHoldsTurn.send()
            if let record = await records.next() { numbers.append((record.event as? Tapped)?.number ?? -1) }
            return numbers
        }
        sut.track(Tapped(number: 0))
        try await firstHoldsTurn.execute()

        let actualSecond = await withTaskGroup(of: Int?.self) { group in
            // A task added to a cancelled group starts cancelled.
            group.cancelAll()
            group.addTask {
                var records = sut.records.makeAsyncIterator()
                let record = await records.next()
                return (record?.event as? Tapped)?.number
            }
            return await group.next() ?? -1
        }
        sut.track(Tapped(number: 1))
        let actualFirst = await first.value
        await sut.finish()

        #expect(actualSecond == expectedSecond)
        #expect(actualFirst == expectedFirst)
    }

    @Test("A reader that starts between the first reader's reads waits too, and the first keeps every record")
    func readerBetweenReadsWaits() async throws {
        let sut = Tracker()
        let firstHoldsTurn = SingleValueSubject<Void>()
        let firstReadsOn = SingleValueSubject<Void>()
        let secondAboutToRead = SingleValueSubject<Void>()
        let expectedFirst = [0, 1, 2]
        let expectedSecond = [3]
        let first = Task {
            var records = sut.records.makeAsyncIterator()
            var numbers: [Int] = []
            if let record = await records.next() { numbers.append((record.event as? Tapped)?.number ?? -1) }
            try? firstHoldsTurn.send()
            // Not reading while the second reader starts and a record arrives.
            try? await firstReadsOn.execute()
            for _ in 1 ... 2 {
                guard let record = await records.next() else { break }
                numbers.append((record.event as? Tapped)?.number ?? -1)
            }
            return numbers
        }
        sut.track(Tapped(number: 0))
        try await firstHoldsTurn.execute()
        let second = Task {
            var numbers: [Int] = []
            try? secondAboutToRead.send()
            for await record in sut.records {
                numbers.append((record.event as? Tapped)?.number ?? -1)
            }
            return numbers
        }
        try await secondAboutToRead.execute()

        sut.track(Tapped(number: 1))
        await sut.flush()
        try firstReadsOn.send()
        sut.track(Tapped(number: 2))
        let actualFirst = await first.value
        sut.track(Tapped(number: 3))
        await sut.finish()
        let actualSecond = await second.value

        #expect(actualFirst == expectedFirst)
        #expect(actualSecond == expectedSecond)
    }
}
