import AsyncQueues
import Testing

@Suite("AsyncQueue.Continuation", .timeLimit(.minutes(1)))
struct AsyncQueueContinuationTests {
    @Test("A continuation's queue reads every element enqueued, in order, then ends once it is finished")
    func enqueueThenFinish() async {
        let sut = AsyncQueue<Int>.Continuation(name: "numbers")
        let queue = sut.queue
        let expected = [1, 2, 3]

        sut.enqueue(1)
        sut.enqueue(2)
        sut.enqueue(3)
        sut.finish()

        var actual: [Int] = []
        for await number in queue {
            actual.append(number)
        }
        #expect(actual == expected)
    }

    @Test("An element enqueued after finish() is dropped")
    func enqueueAfterFinish() async {
        let sut = AsyncQueue<Int>.Continuation(name: "numbers")
        let queue = sut.queue
        let expected = [1]

        sut.enqueue(1)
        sut.finish()
        sut.enqueue(2)

        var actual: [Int] = []
        for await number in queue {
            actual.append(number)
        }
        #expect(actual == expected)
    }

    @Test("The queue ends once the continuation and every copy of it are gone, after the elements kept")
    func endsWithLastCopy() async {
        var sut: AsyncQueue<Int>.Continuation? = AsyncQueue<Int>.Continuation(name: "numbers")
        var copy = sut
        let queue = sut?.queue
        let expected = [1, 2]

        sut?.enqueue(1)
        copy?.enqueue(2)
        sut = nil
        copy = nil

        var actual: [Int] = []
        if let queue {
            for await number in queue {
                actual.append(number)
            }
        }
        #expect(actual == expected)
    }

    @Test("The queue stays open while a copy of the continuation remains")
    func openWhileCopyRemains() async {
        var sut: AsyncQueue<Int>.Continuation? = AsyncQueue<Int>.Continuation(name: "numbers")
        let copy = sut
        let queue = sut?.queue
        let expected = [1, 2]

        sut?.enqueue(1)
        sut = nil
        copy?.enqueue(2)
        copy?.finish()

        var actual: [Int] = []
        if let queue {
            for await number in queue {
                actual.append(number)
            }
        }
        #expect(actual == expected)
    }

    @Test("A continuation's queue keeps every element no one has read, without a bound")
    func unbounded() async {
        let sut = AsyncQueue<Int>.Continuation(name: "numbers")
        let queue = sut.queue
        let expected = Array(0 ..< 1_000)

        for number in expected {
            sut.enqueue(number)
        }
        sut.finish()

        var actual: [Int] = []
        for await number in queue {
            actual.append(number)
        }
        #expect(actual == expected)
    }
}
