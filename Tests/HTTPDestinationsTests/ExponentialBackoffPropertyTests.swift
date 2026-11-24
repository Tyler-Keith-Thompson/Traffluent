import HTTPDestinations
import PropertyBased
import Testing

@Suite("ExponentialBackoff: properties")
struct ExponentialBackoffPropertyTests {
    @Test("Each wait is the initial delay doubled once per earlier retry, or the maximum if that is less, as a naive reference computes it")
    func matchesReference() async {
        await propertyCheck(count: 500, input: Gen.int(in: 1 ... 1_000), Gen.int(in: 0 ... 20_000), Gen.int(in: 1 ... 40)) { initialMilliseconds, extraMilliseconds, retry in
            let initial = Duration.milliseconds(initialMilliseconds)
            let maximum = Duration.milliseconds(initialMilliseconds + extraMilliseconds)
            let sut = ExponentialBackoff(initialDelay: initial, maximumDelay: maximum)
            // 1,000 ms doubled 39 times is about 5.5e14 ms, well inside Int.
            let expected = min(Duration.milliseconds(initialMilliseconds << (retry - 1)), maximum)

            let actual = sut.delay(beforeRetry: retry)

            #expect(actual == expected)
        }
    }
}
