import Afluent
import AsyncQueues
import DequeModule
import Testing

@Suite("AsyncQueue", .timeLimit(.minutes(1)))
struct AsyncQueueTests {
    @Test("Elements enqueued before the first read are read in the order enqueued, then nil once the queue is finished")
    func readsInOrderThenEnds() async {
        let sut = AsyncQueue<Int>(name: "numbers")
        let expected = [1, 2, 3]
        sut.enqueue(1)
        sut.enqueue(2)
        sut.enqueue(3)
        sut.finish()

        var actual: [Int] = []
        for await number in sut {
            actual.append(number)
        }

        #expect(actual == expected)
    }

    @Test("A read waiting for an element gets the one enqueued next")
    func waitingReadGetsNext() async throws {
        let sut = AsyncQueue<Int>(name: "numbers")
        let aboutToRead = SingleValueSubject<Void>()
        let expected: Int? = 7
        let reader = Task {
            var iterator = sut.makeAsyncIterator()
            try? aboutToRead.send()
            return await iterator.next()
        }
        try await aboutToRead.execute()

        sut.enqueue(7)

        let actual = await reader.value
        #expect(actual == expected)
    }

    @Test("A read waiting for an element returns nil once the queue is finished")
    func waitingReadEndsAtFinish() async throws {
        let sut = AsyncQueue<Int>(name: "numbers")
        let aboutToRead = SingleValueSubject<Void>()
        let expected: Int? = nil
        let reader = Task {
            var iterator = sut.makeAsyncIterator()
            try? aboutToRead.send()
            return await iterator.next()
        }
        try await aboutToRead.execute()

        sut.finish()

        let actual = await reader.value
        #expect(actual == expected)
    }

    @Test("An empty queue that is finished ends at once")
    func emptyFinishedEnds() async {
        let sut = AsyncQueue<Int>(name: "numbers")
        let expected: [Int] = []
        sut.finish()

        var actual: [Int] = []
        for await number in sut {
            actual.append(number)
        }

        #expect(actual == expected)
    }

    @Test("A queue made finished ends at once")
    func madeFinishedEnds() async {
        let sut = AsyncQueue<Int>.finished(name: "numbers")
        let expected: Int? = nil
        var iterator = sut.makeAsyncIterator()

        let actual = await iterator.next()

        #expect(actual == expected)
    }

    @Test("An element enqueued after the queue is finished is dropped")
    func enqueueAfterFinishDropped() async {
        let sut = AsyncQueue<Int>(name: "numbers")
        let expected = [1]
        sut.enqueue(1)
        sut.finish()

        sut.enqueue(2)

        var actual: [Int] = []
        for await number in sut {
            actual.append(number)
        }
        #expect(actual == expected)
    }

    @Test("Copies of a queue share its elements")
    func copiesShare() async {
        let sut = AsyncQueue<Int>(name: "numbers")
        let copy = sut
        let expected = [1, 2]

        copy.enqueue(1)
        sut.enqueue(2)
        copy.finish()

        var actual: [Int] = []
        for await number in sut {
            actual.append(number)
        }
        #expect(actual == expected)
    }

    @Test("A read whose task is already cancelled returns nil and takes nothing: the next read gets the element")
    func cancelledReadTakesNothing() async {
        let sut = AsyncQueue<Int>(name: "numbers")
        let expectedCancelled: Int? = nil
        let expectedNext = [1]
        sut.enqueue(1)

        let actualCancelled = await withTaskGroup(of: Int?.self) { group in
            // A task added to a cancelled group starts cancelled.
            group.cancelAll()
            group.addTask {
                var iterator = sut.makeAsyncIterator()
                return await iterator.next()
            }
            return await group.next() ?? -1
        }
        sut.finish()
        var actualNext: [Int] = []
        for await number in sut {
            actualNext.append(number)
        }

        #expect(actualCancelled == expectedCancelled)
        #expect(actualNext == expectedNext)
    }

    @Test("A read cancelled while it waits returns nil, and the element enqueued after it goes to the next read")
    func cancelledWaitingRead() async throws {
        let sut = AsyncQueue<Int>(name: "numbers")
        let aboutToRead = SingleValueSubject<Void>()
        let expectedCancelled: Int? = nil
        let expectedNext = [1]
        let reader = Task {
            var iterator = sut.makeAsyncIterator()
            try? aboutToRead.send()
            return await iterator.next()
        }
        try await aboutToRead.execute()

        reader.cancel()
        let actualCancelled = await reader.value
        sut.enqueue(1)
        sut.finish()

        var actualNext: [Int] = []
        for await number in sut {
            actualNext.append(number)
        }
        #expect(actualCancelled == expectedCancelled)
        #expect(actualNext == expectedNext)
    }

    @Test("Buffering the newest 2 keeps the 2 enqueued last while nothing reads")
    func newestKeepsLimit() async {
        let sut = AsyncQueue<Int>(name: "numbers", buffering: .newest(2))
        let expected = [3, 4]
        for number in 1 ... 4 {
            sut.enqueue(number)
        }
        sut.finish()

        var actual: [Int] = []
        for await number in sut {
            actual.append(number)
        }

        #expect(actual == expected)
    }

    @Test("Buffering the newest 2 keeps both of 2 elements, the boundary")
    func newestAtLimit() async {
        let sut = AsyncQueue<Int>(name: "numbers", buffering: .newest(2))
        let expected = [1, 2]
        sut.enqueue(1)
        sut.enqueue(2)
        sut.finish()

        var actual: [Int] = []
        for await number in sut {
            actual.append(number)
        }

        #expect(actual == expected)
    }

    @Test("Buffering the newest 1 keeps only the last element")
    func newestOne() async {
        let sut = AsyncQueue<Int>(name: "numbers", buffering: .newest(1))
        let expected = [3]
        sut.enqueue(1)
        sut.enqueue(2)
        sut.enqueue(3)
        sut.finish()

        var actual: [Int] = []
        for await number in sut {
            actual.append(number)
        }

        #expect(actual == expected)
    }

    @Test("Buffering the newest 0, or fewer, keeps no element while nothing reads")
    func newestNoneKeepsNothing() async {
        let zero = AsyncQueue<Int>(name: "numbers", buffering: .newest(0))
        let negative = AsyncQueue<Int>(name: "numbers", buffering: .newest(-1))
        let expected: [Int] = []
        for sut in [zero, negative] {
            sut.enqueue(1)
            sut.enqueue(2)
            sut.finish()
        }

        var actualZero: [Int] = []
        for await number in zero {
            actualZero.append(number)
        }
        var actualNegative: [Int] = []
        for await number in negative {
            actualNegative.append(number)
        }

        #expect(actualZero == expected)
        #expect(actualNegative == expected)
    }

    @Test("A buffering of its own merges each element into those waiting as it says")
    func customBufferingMerges() async {
        let sut = AsyncQueue<Int>(name: "numbers", buffering: .init(adding: { number, waiting in
            if let last = waiting.last, last < 10 {
                waiting[waiting.count - 1] = last + number
            } else {
                waiting.append(number)
            }
        }))
        let expected = [10, 5]
        for number in [1, 2, 3, 4, 5] {
            sut.enqueue(number)
        }
        sut.finish()

        var actual: [Int] = []
        for await number in sut {
            actual.append(number)
        }

        #expect(actual == expected)
    }
}
