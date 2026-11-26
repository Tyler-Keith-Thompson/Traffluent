import HTTPDestinations
import Testing

@Suite("ExponentialBackoff")
struct ExponentialBackoffTests {
    @Test("The default waits 1 s before the first retry, doubling to 60 s, then 60 s before every retry after")
    func defaultWaits() throws {
        let sut = ExponentialBackoff()
        let expected: [Duration] = [.seconds(1), .seconds(2), .seconds(4), .seconds(8), .seconds(16), .seconds(32), .seconds(60), .seconds(60)]

        let actual = try (1 ... 8).map { try sut.delay(beforeRetry: $0) }

        #expect(actual == expected)
    }

    @Test("A wait that doubles exactly onto the maximum is the maximum, and stays there")
    func doublesOntoMaximum() throws {
        let sut = try ExponentialBackoff(initialDelay: .milliseconds(250), maximumDelay: .seconds(1))
        let expected: [Duration] = [.milliseconds(250), .milliseconds(500), .seconds(1), .seconds(1)]

        let actual = try (1 ... 4).map { try sut.delay(beforeRetry: $0) }

        #expect(actual == expected)
    }

    @Test("A wait doubles while twice it is within an odd maximum, to the attosecond")
    func oddMaximum() throws {
        let sut = try ExponentialBackoff(initialDelay: Duration(secondsComponent: 0, attosecondsComponent: 1), maximumDelay: Duration(secondsComponent: 0, attosecondsComponent: 3))
        let expected = [1, 2, 3, 3].map { Duration(secondsComponent: 0, attosecondsComponent: $0) }

        let actual = try (1 ... 4).map { try sut.delay(beforeRetry: $0) }

        #expect(actual == expected)
    }

    @Test("A backoff whose initial delay is its maximum waits that long before every retry")
    func initialIsMaximum() throws {
        let sut = try ExponentialBackoff(initialDelay: .seconds(5), maximumDelay: .seconds(5))
        let expected: [Duration] = [.seconds(5), .seconds(5), .seconds(5)]

        let actual = try [1, 2, 100].map { try sut.delay(beforeRetry: $0) }

        #expect(actual == expected)
    }

    @Test("Far past where doubling would overflow a Duration, the wait is the maximum")
    func farRetry() throws {
        let sut = try ExponentialBackoff(initialDelay: .nanoseconds(1), maximumDelay: .seconds(Int64.max))
        let expected = Duration.seconds(Int64.max)

        let actual = try sut.delay(beforeRetry: .max)

        #expect(actual == expected)
    }

    @Test("The initializer keeps the delays it is given")
    func keepsDelays() throws {
        let expectedInitial = Duration.milliseconds(1)
        let expectedMaximum = Duration.milliseconds(2)

        let sut = try ExponentialBackoff(initialDelay: expectedInitial, maximumDelay: expectedMaximum)

        #expect(sut.initialDelay == expectedInitial)
        #expect(sut.maximumDelay == expectedMaximum)
    }

    @Test("The initializer accepts a maximum delay equal to the initial one, and the smallest positive initial delay")
    func valid() throws {
        let expectedEqual: Duration = .seconds(2)
        let expectedSmallest: Duration = .nanoseconds(1)

        let equal = try ExponentialBackoff(initialDelay: .seconds(2), maximumDelay: .seconds(2))
        let smallest = try ExponentialBackoff(initialDelay: .nanoseconds(1), maximumDelay: .nanoseconds(1))

        #expect(equal.initialDelay == expectedEqual)
        #expect(equal.maximumDelay == expectedEqual)
        #expect(smallest.initialDelay == expectedSmallest)
    }

    @Test("Waiting before a retry numbered below 1 throws NonPositiveRetry", arguments: [0, -1, Int.min])
    func retryBelowOne(_ retry: Int) {
        let sut = ExponentialBackoff()

        #expect(throws: NonPositiveRetry()) {
            try sut.delay(beforeRetry: retry)
        }
    }

    @Test("The initializer throws InvalidBackoff for an initial delay that isn't positive", arguments: [Duration.zero, .nanoseconds(-1), .seconds(-5)])
    func notPositive(initial: Duration) {
        #expect(throws: InvalidBackoff()) {
            try ExponentialBackoff(initialDelay: initial, maximumDelay: .seconds(1))
        }
    }

    @Test("The initializer throws InvalidBackoff for a maximum delay less than the initial one")
    func maximumBelowInitial() {
        let initial = Duration.seconds(2)
        let maximum = Duration.seconds(2) - .nanoseconds(1)

        #expect(throws: InvalidBackoff()) {
            try ExponentialBackoff(initialDelay: initial, maximumDelay: maximum)
        }
    }
}
