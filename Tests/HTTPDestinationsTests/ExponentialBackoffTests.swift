import HTTPDestinations
import Testing

@Suite("ExponentialBackoff")
struct ExponentialBackoffTests {
    @Test("The default waits 1 s before the first retry, doubling to 60 s, then 60 s before every retry after")
    func defaultWaits() {
        let sut = ExponentialBackoff()
        let expected: [Duration] = [.seconds(1), .seconds(2), .seconds(4), .seconds(8), .seconds(16), .seconds(32), .seconds(60), .seconds(60)]

        let actual = (1 ... 8).map { sut.delay(beforeRetry: $0) }

        #expect(actual == expected)
    }

    @Test("A wait that doubles exactly onto the maximum is the maximum, and stays there")
    func doublesOntoMaximum() {
        let sut = ExponentialBackoff(initialDelay: .milliseconds(250), maximumDelay: .seconds(1))
        let expected: [Duration] = [.milliseconds(250), .milliseconds(500), .seconds(1), .seconds(1)]

        let actual = (1 ... 4).map { sut.delay(beforeRetry: $0) }

        #expect(actual == expected)
    }

    @Test("A wait doubles while twice it is within an odd maximum, to the attosecond")
    func oddMaximum() {
        let sut = ExponentialBackoff(initialDelay: Duration(secondsComponent: 0, attosecondsComponent: 1), maximumDelay: Duration(secondsComponent: 0, attosecondsComponent: 3))
        let expected = [1, 2, 3, 3].map { Duration(secondsComponent: 0, attosecondsComponent: $0) }

        let actual = (1 ... 4).map { sut.delay(beforeRetry: $0) }

        #expect(actual == expected)
    }

    @Test("A backoff whose initial delay is its maximum waits that long before every retry")
    func initialIsMaximum() {
        let sut = ExponentialBackoff(initialDelay: .seconds(5), maximumDelay: .seconds(5))
        let expected: [Duration] = [.seconds(5), .seconds(5), .seconds(5)]

        let actual = [1, 2, 100].map { sut.delay(beforeRetry: $0) }

        #expect(actual == expected)
    }

    @Test("Far past where doubling would overflow a Duration, the wait is the maximum")
    func farRetry() {
        let sut = ExponentialBackoff(initialDelay: .nanoseconds(1), maximumDelay: .seconds(Int64.max))
        let expected = Duration.seconds(Int64.max)

        let actual = sut.delay(beforeRetry: .max)

        #expect(actual == expected)
    }

    @Test("The initializer keeps the delays it is given")
    func keepsDelays() {
        let expectedInitial = Duration.milliseconds(1)
        let expectedMaximum = Duration.milliseconds(2)

        let sut = ExponentialBackoff(initialDelay: expectedInitial, maximumDelay: expectedMaximum)

        #expect(sut.initialDelay == expectedInitial)
        #expect(sut.maximumDelay == expectedMaximum)
    }

    @Test("The checked spelling makes the same backoff as the plain one for valid delays")
    func checkedValid() throws {
        let expected = ExponentialBackoff(initialDelay: .seconds(2), maximumDelay: .seconds(2))

        let actual = try ExponentialBackoff(checkedInitialDelay: .seconds(2), maximumDelay: .seconds(2))

        #expect(actual == expected)
    }

    @Test("The checked spelling throws InvalidBackoff for an initial delay that isn't positive", arguments: [Duration.zero, .nanoseconds(-1), .seconds(-5)])
    func checkedNotPositive(initial: Duration) {
        #expect(throws: InvalidBackoff()) {
            try ExponentialBackoff(checkedInitialDelay: initial, maximumDelay: .seconds(1))
        }
    }

    @Test("The checked spelling throws InvalidBackoff for a maximum delay less than the initial one")
    func checkedMaximumBelowInitial() {
        let initial = Duration.seconds(2)
        let maximum = Duration.seconds(2) - .nanoseconds(1)

        #expect(throws: InvalidBackoff()) {
            try ExponentialBackoff(checkedInitialDelay: initial, maximumDelay: maximum)
        }
    }
}
