// Which reader reaches the queue first decides which path a read takes, so these tests run their
// tasks on the main serial executor (swift-concurrency-extras), which runs every job in the order
// it was enqueued: a reader that sends its gate and then reads is waiting for its turn before the
// test resumes. It changes a global hook, so the suite runs its tests one at a time.
import Afluent
import AsyncQueues
import ConcurrencyExtras
import Testing

@MainActor
@Suite("AsyncQueue: one reader at a time", .serialized, .timeLimit(.minutes(1)))
struct AsyncQueueReadTurnTests {
    @Test("A second reader that starts while the first waits gets none of the first's elements, and once the first's iterator is released reads on in order")
    func secondReaderWaitsForRelease() async throws {
        try await withMainSerialExecutor {
            let sut = AsyncQueue<Int>(name: "numbers")
            let firstHoldsTurn = SingleValueSubject<Void>()
            let secondAboutToRead = SingleValueSubject<Void>()
            let expectedFirst = [0, 1, 2, 3]
            let expectedSecond = [4, 5]
            let first = Task {
                var iterator = sut.makeAsyncIterator()
                var numbers: [Int] = []
                // The first read takes the turn, which the iterator keeps until this task releases it.
                if let number = await iterator.next() { numbers.append(number) }
                try? firstHoldsTurn.send()
                for _ in 1 ... 3 {
                    guard let number = await iterator.next() else { break }
                    numbers.append(number)
                }
                return numbers
            }
            sut.enqueue(0)
            try await firstHoldsTurn.execute()
            let second = Task {
                var numbers: [Int] = []
                try? secondAboutToRead.send()
                for await number in sut {
                    numbers.append(number)
                }
                return numbers
            }
            try await secondAboutToRead.execute()

            sut.enqueue(1)
            sut.enqueue(2)
            sut.enqueue(3)
            let actualFirst = await first.value
            sut.enqueue(4)
            sut.enqueue(5)
            sut.finish()
            let actualSecond = await second.value

            #expect(actualFirst == expectedFirst)
            #expect(actualSecond == expectedSecond)
        }
    }

    @Test("A second reader that starts while the first reads on ends once the first's iteration ends and the queue finishes, the first getting every element")
    func secondReaderEndsAfterFirst() async throws {
        try await withMainSerialExecutor {
            let sut = AsyncQueue<Int>(name: "numbers")
            let firstHoldsTurn = SingleValueSubject<Void>()
            let secondAboutToRead = SingleValueSubject<Void>()
            let expectedFirst = [0, 1, 2]
            let expectedSecond: [Int] = []
            let first = Task {
                var numbers: [Int] = []
                for await number in sut {
                    numbers.append(number)
                    if number == 0 { try? firstHoldsTurn.send() }
                }
                return numbers
            }
            sut.enqueue(0)
            try await firstHoldsTurn.execute()
            let second = Task {
                var numbers: [Int] = []
                try? secondAboutToRead.send()
                for await number in sut {
                    numbers.append(number)
                }
                return numbers
            }
            try await secondAboutToRead.execute()

            sut.enqueue(1)
            sut.enqueue(2)
            sut.finish()
            let actualFirst = await first.value
            let actualSecond = await second.value

            #expect(actualFirst == expectedFirst)
            #expect(actualSecond == expectedSecond)
        }
    }

    @Test("Once the first reader's iteration ends, a waiting reader reads on in order, though the first's iterator is still held")
    func secondReaderWaitsForEnd() async throws {
        try await withMainSerialExecutor {
            let sut = AsyncQueue<Int>(name: "numbers")
            // Its job ignores the cancelled task awaiting it, so that task holds its iterator until
            // the test lets it go.
            let holder = SerialTaskQueue()
            let firstHoldsTurn = SingleValueSubject<Void>()
            let firstEnded = SingleValueSubject<Void>()
            let releaseFirst = SingleValueSubject<Void>()
            let expectedFirstEnd: Int? = nil
            let expectedSecond = [1, 2]
            let first = Task {
                var iterator = sut.makeAsyncIterator()
                _ = await iterator.next()
                try? firstHoldsTurn.send()
                // Cancelled while it waits: the iteration's end.
                let end = await iterator.next()
                try? firstEnded.send()
                try? await holder.enqueue { try? await releaseFirst.execute() }
                withExtendedLifetime(iterator) {}
                return end
            }
            sut.enqueue(0)
            try await firstHoldsTurn.execute()
            let second = Task {
                var numbers: [Int] = []
                var iterator = sut.makeAsyncIterator()
                for _ in 1 ... 2 {
                    guard let number = await iterator.next() else { break }
                    numbers.append(number)
                }
                return numbers
            }

            first.cancel()
            try await firstEnded.execute()
            sut.enqueue(1)
            sut.enqueue(2)
            let actualSecond = await second.value
            try releaseFirst.send()
            let actualFirstEnd = await first.value
            sut.finish()

            #expect(actualFirstEnd == expectedFirstEnd)
            #expect(actualSecond == expectedSecond)
        }
    }

    @Test("A waiting reader whose task is cancelled returns nil, and the reader holding the turn keeps every element")
    func waitingReaderCancelled() async throws {
        try await withMainSerialExecutor {
            let sut = AsyncQueue<Int>(name: "numbers")
            let firstHoldsTurn = SingleValueSubject<Void>()
            let secondAboutToRead = SingleValueSubject<Void>()
            let expectedFirst = [0, 1, 2]
            let expectedSecond: Int? = nil
            let first = Task {
                var iterator = sut.makeAsyncIterator()
                var numbers: [Int] = []
                if let number = await iterator.next() { numbers.append(number) }
                try? firstHoldsTurn.send()
                for _ in 1 ... 2 {
                    guard let number = await iterator.next() else { break }
                    numbers.append(number)
                }
                return numbers
            }
            sut.enqueue(0)
            try await firstHoldsTurn.execute()
            let second = Task {
                var iterator = sut.makeAsyncIterator()
                try? secondAboutToRead.send()
                return await iterator.next()
            }
            try await secondAboutToRead.execute()

            second.cancel()
            let actualSecond = await second.value
            sut.enqueue(1)
            sut.enqueue(2)
            let actualFirst = await first.value
            sut.finish()

            #expect(actualSecond == expectedSecond)
            #expect(actualFirst == expectedFirst)
        }
    }

    @Test("A reader whose task is already cancelled as another holds the turn returns nil rather than wait")
    func cancelledReaderDoesNotWait() async throws {
        try await withMainSerialExecutor {
            let sut = AsyncQueue<Int>(name: "numbers")
            let firstHoldsTurn = SingleValueSubject<Void>()
            let expectedFirst = [0, 1]
            let expectedSecond: Int? = nil
            let first = Task {
                var iterator = sut.makeAsyncIterator()
                var numbers: [Int] = []
                if let number = await iterator.next() { numbers.append(number) }
                try? firstHoldsTurn.send()
                if let number = await iterator.next() { numbers.append(number) }
                return numbers
            }
            sut.enqueue(0)
            try await firstHoldsTurn.execute()

            let actualSecond = await withTaskGroup(of: Int?.self) { group in
                // A task added to a cancelled group starts cancelled.
                group.cancelAll()
                group.addTask {
                    var iterator = sut.makeAsyncIterator()
                    return await iterator.next()
                }
                return await group.next() ?? -1
            }
            sut.enqueue(1)
            let actualFirst = await first.value
            sut.finish()

            #expect(actualSecond == expectedSecond)
            #expect(actualFirst == expectedFirst)
        }
    }

    @Test("A reader that starts between the first reader's reads waits too, and the first keeps every element")
    func readerBetweenReadsWaits() async throws {
        try await withMainSerialExecutor {
            let sut = AsyncQueue<Int>(name: "numbers")
            let firstHoldsTurn = SingleValueSubject<Void>()
            let firstReadsOn = SingleValueSubject<Void>()
            let secondAboutToRead = SingleValueSubject<Void>()
            let expectedFirst = [0, 1, 2]
            let expectedSecond = [3]
            let first = Task {
                var iterator = sut.makeAsyncIterator()
                var numbers: [Int] = []
                if let number = await iterator.next() { numbers.append(number) }
                try? firstHoldsTurn.send()
                // Not reading while the second reader starts and an element arrives.
                try? await firstReadsOn.execute()
                for _ in 1 ... 2 {
                    guard let number = await iterator.next() else { break }
                    numbers.append(number)
                }
                return numbers
            }
            sut.enqueue(0)
            try await firstHoldsTurn.execute()
            let second = Task {
                var numbers: [Int] = []
                try? secondAboutToRead.send()
                for await number in sut {
                    numbers.append(number)
                }
                return numbers
            }
            try await secondAboutToRead.execute()

            sut.enqueue(1)
            try firstReadsOn.send()
            sut.enqueue(2)
            let actualFirst = await first.value
            sut.enqueue(3)
            sut.finish()
            let actualSecond = await second.value

            #expect(actualFirst == expectedFirst)
            #expect(actualSecond == expectedSecond)
        }
    }

    @Test("A reader holding the turn whose read is cancelled returns nil and takes nothing, and a waiting reader then reads on from that element")
    func holderCancelledHandsOn() async throws {
        try await withMainSerialExecutor {
            let sut = AsyncQueue<Int>(name: "numbers")
            let holder = SerialTaskQueue()
            let firstHoldsTurn = SingleValueSubject<Void>()
            let firstEnded = SingleValueSubject<Void>()
            let releaseFirst = SingleValueSubject<Void>()
            let secondAboutToRead = SingleValueSubject<Void>()
            let expectedFirst = [0]
            let expectedSecond = [1, 2]
            let first = Task {
                var iterator = sut.makeAsyncIterator()
                var numbers: [Int] = []
                if let number = await iterator.next() { numbers.append(number) }
                try? firstHoldsTurn.send()
                if let number = await iterator.next() { numbers.append(number) }
                try? firstEnded.send()
                try? await holder.enqueue { try? await releaseFirst.execute() }
                withExtendedLifetime(iterator) {}
                return numbers
            }
            sut.enqueue(0)
            try await firstHoldsTurn.execute()
            let second = Task {
                var numbers: [Int] = []
                try? secondAboutToRead.send()
                for await number in sut {
                    numbers.append(number)
                }
                return numbers
            }
            try await secondAboutToRead.execute()

            first.cancel()
            try await firstEnded.execute()
            sut.enqueue(1)
            sut.enqueue(2)
            sut.finish()
            let actualSecond = await second.value
            try releaseFirst.send()
            let actualFirst = await first.value

            #expect(actualFirst == expectedFirst)
            #expect(actualSecond == expectedSecond)
        }
    }

    @Test("A reader handed the turn holds it: a third reader waits until the second's iteration ends, then reads on")
    func handedTurnIsHeld() async throws {
        try await withMainSerialExecutor {
            let sut = AsyncQueue<Int>(name: "numbers")
            let firstHoldsTurn = SingleValueSubject<Void>()
            let secondAboutToRead = SingleValueSubject<Void>()
            let secondHoldsTurn = SingleValueSubject<Void>()
            let thirdAboutToRead = SingleValueSubject<Void>()
            let expectedFirst = [0, 1]
            let expectedSecond = [2, 3]
            let expectedThird = [4]
            let first = Task {
                var iterator = sut.makeAsyncIterator()
                var numbers: [Int] = []
                if let number = await iterator.next() { numbers.append(number) }
                try? firstHoldsTurn.send()
                if let number = await iterator.next() { numbers.append(number) }
                return numbers
            }
            sut.enqueue(0)
            try await firstHoldsTurn.execute()
            let second = Task {
                var iterator = sut.makeAsyncIterator()
                var numbers: [Int] = []
                try? secondAboutToRead.send()
                if let number = await iterator.next() { numbers.append(number) }
                try? secondHoldsTurn.send()
                if let number = await iterator.next() { numbers.append(number) }
                return numbers
            }
            try await secondAboutToRead.execute()
            sut.enqueue(1)
            // The first's iterator is released as its task returns, handing the turn to the second.
            let actualFirst = await first.value
            sut.enqueue(2)
            try await secondHoldsTurn.execute()
            let third = Task {
                var numbers: [Int] = []
                try? thirdAboutToRead.send()
                for await number in sut {
                    numbers.append(number)
                }
                return numbers
            }
            try await thirdAboutToRead.execute()

            sut.enqueue(3)
            let actualSecond = await second.value
            sut.enqueue(4)
            sut.finish()
            let actualThird = await third.value

            #expect(actualFirst == expectedFirst)
            #expect(actualSecond == expectedSecond)
            #expect(actualThird == expectedThird)
        }
    }

    @Test("Readers waiting for the turn take it in the order they started to wait")
    func waitersTakeTurnInOrder() async throws {
        try await withMainSerialExecutor {
            let sut = AsyncQueue<Int>(name: "numbers")
            let firstHoldsTurn = SingleValueSubject<Void>()
            let secondAboutToRead = SingleValueSubject<Void>()
            let thirdAboutToRead = SingleValueSubject<Void>()
            let expectedFirst = [0, 1]
            let expectedSecond = [2]
            let expectedThird = [3]
            let first = Task {
                var iterator = sut.makeAsyncIterator()
                var numbers: [Int] = []
                if let number = await iterator.next() { numbers.append(number) }
                try? firstHoldsTurn.send()
                if let number = await iterator.next() { numbers.append(number) }
                return numbers
            }
            sut.enqueue(0)
            try await firstHoldsTurn.execute()
            let second = Task {
                var iterator = sut.makeAsyncIterator()
                var numbers: [Int] = []
                try? secondAboutToRead.send()
                if let number = await iterator.next() { numbers.append(number) }
                return numbers
            }
            try await secondAboutToRead.execute()
            let third = Task {
                var numbers: [Int] = []
                try? thirdAboutToRead.send()
                for await number in sut {
                    numbers.append(number)
                }
                return numbers
            }
            try await thirdAboutToRead.execute()

            sut.enqueue(1)
            let actualFirst = await first.value
            sut.enqueue(2)
            sut.enqueue(3)
            sut.finish()
            let actualSecond = await second.value
            let actualThird = await third.value

            #expect(actualFirst == expectedFirst)
            #expect(actualSecond == expectedSecond)
            #expect(actualThird == expectedThird)
        }
    }

    @Test("A copy of the iterator holding the turn that reads from another task while the original waits returns nil, and the original keeps the turn and every element")
    func copyReadingConcurrentlyKeepsTurn() async throws {
        try await withMainSerialExecutor {
            let sut = AsyncQueue<Int>(name: "numbers")
            let firstAboutToRead = SingleValueSubject<Void>()
            let firstHasRead = SingleValueSubject<Void>()
            let firstReadsOn = SingleValueSubject<Void>()
            let laterAboutToRead = SingleValueSubject<Void>()
            let expectedCopy: Int? = nil
            let expectedFirst = [1, 2]
            let expectedLater: [Int] = []
            let original = sut.makeAsyncIterator()
            // The iterator isn't Sendable, so only unchecked code reads copies of it from two
            // tasks, as this test does on purpose.
            let first = Task {
                nonisolated(unsafe) var iterator = original
                var numbers: [Int] = []
                try? firstAboutToRead.send()
                if let number = await iterator.next() { numbers.append(number) }
                try? firstHasRead.send()
                // Not reading while a later reader starts and an element arrives.
                try? await firstReadsOn.execute()
                while let number = await iterator.next() {
                    numbers.append(number)
                }
                return numbers
            }
            try await firstAboutToRead.execute()
            let copy = Task {
                nonisolated(unsafe) var iterator = original
                return await iterator.next()
            }
            let actualCopy = await copy.value
            sut.enqueue(1)
            try await firstHasRead.execute()
            let later = Task {
                var numbers: [Int] = []
                try? laterAboutToRead.send()
                for await number in sut {
                    numbers.append(number)
                }
                return numbers
            }
            try await laterAboutToRead.execute()

            sut.enqueue(2)
            sut.finish()
            try firstReadsOn.send()
            let actualFirst = await first.value
            let actualLater = await later.value

            #expect(actualCopy == expectedCopy)
            #expect(actualFirst == expectedFirst)
            #expect(actualLater == expectedLater)
        }
    }
}
