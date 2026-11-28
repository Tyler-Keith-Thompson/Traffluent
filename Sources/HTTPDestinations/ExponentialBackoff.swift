/// How long ``HTTPDestination`` waits before each new attempt at a batch that wasn't delivered:
/// binary exponential backoff, each nominal wait twice the one before, up to a maximum, with
/// jitter.
///
/// `ExponentialBackoff()` has nominal waits of 1, 2, 4, 8, 16 and 32 seconds, then 60 seconds for
/// every retry after that, with full jitter, as this one does:
///
/// ```swift
/// let backoff = try ExponentialBackoff(initialDelay: .seconds(1), maximumDelay: .seconds(60), jitter: .full)
/// ```
///
/// ``delay(beforeRetry:)`` is the nominal wait. What ``HTTPDestination`` sleeps before each retry
/// depends on the backoff's jitter:
///
/// - ``Jitter/full``, the default: a random wait, at least zero and less than the nominal one,
///   drawn afresh before each retry from the destination's random number generator.
/// - ``Jitter/none``: the nominal wait. It is exact when both delays count their attoseconds in
///   53 significant bits or fewer, as any whole number of milliseconds under 295 seconds does;
///   otherwise it is within about one part in 2⁵³ of it.
///
/// Jitter is on by default because apps tend to be refused all at once. A rate limiter's window,
/// or an outage ending, refuses many apps at the same moment. Without jitter they would all retry
/// at the same moments too, and each wave would be refused like the one before. Full jitter
/// spreads each wave over the whole wait. It also halves the average wait, so an app retries
/// about twice as often during a long outage.
public struct ExponentialBackoff: Sendable, Hashable {
    /// How a nominal wait is randomized before ``HTTPDestination`` sleeps it.
    ///
    /// The cases are named after the article "Exponential Backoff And Jitter" on the AWS
    /// Architecture Blog.
    public enum Jitter: Sendable, Hashable {
        /// The nominal wait, exactly.
        case none
        /// A random wait, at least zero and less than the nominal one.
        case full
    }

    /// The nominal wait before the first retry.
    public let initialDelay: Duration
    /// The longest nominal wait, which every retry has once doubling reaches it.
    public let maximumDelay: Duration
    /// How each nominal wait is randomized.
    public let jitter: Jitter

    /// A backoff whose nominal wait is 1 second before the first retry, doubling after it up to
    /// 60 seconds, randomized by `jitter`.
    ///
    /// - Parameter jitter: How each nominal wait is randomized; ``Jitter/full`` by default.
    public init(jitter: Jitter = .full) {
        initialDelay = .seconds(1)
        maximumDelay = .seconds(60)
        self.jitter = jitter
    }

    /// A backoff whose nominal wait is `initialDelay` before the first retry, doubling after it
    /// up to `maximumDelay`, randomized by `jitter`.
    ///
    /// - Parameters:
    ///   - initialDelay: The nominal wait before the first retry.
    ///   - maximumDelay: The longest nominal wait.
    ///   - jitter: How each nominal wait is randomized; ``Jitter/full`` by default.
    /// - Throws: ``InvalidBackoff`` when `initialDelay` isn't positive or `maximumDelay` is less
    ///   than it.
    public init(initialDelay: Duration, maximumDelay: Duration, jitter: Jitter = .full) throws(InvalidBackoff) {
        guard initialDelay > .zero, maximumDelay >= initialDelay else { throw InvalidBackoff() }
        self.initialDelay = initialDelay
        self.maximumDelay = maximumDelay
        self.jitter = jitter
    }

    /// The nominal wait before retry number `retry`: `initialDelay` doubled `retry - 1` times, or
    /// `maximumDelay` if that is less.
    ///
    /// With ``Jitter/full`` jitter, the wait ``HTTPDestination`` sleeps is less than this.
    ///
    /// - Parameter retry: Which retry, counting from 1.
    /// - Returns: The nominal wait before it.
    /// - Complexity: O(min(`retry`, log₂(`maximumDelay` / `initialDelay`))).
    /// - Throws: ``NonPositiveRetry`` when `retry` is below 1.
    public func delay(beforeRetry retry: Int) throws(NonPositiveRetry) -> Duration {
        guard retry >= 1 else { throw NonPositiveRetry() }
        return delay(afterDoubling: retry - 1)
    }

    /// `initialDelay` doubled `doublings` times, or `maximumDelay` if that is less; `initialDelay`
    /// for none, or fewer.
    func delay(afterDoubling doublings: Int) -> Duration {
        var delay = initialDelay
        var doublings = doublings
        while doublings > 0 {
            // Whether twice the wait passes the maximum, asked of the difference: exact, where
            // `maximumDelay / 2` rounds down, and unable to overflow, as doubling first could.
            guard delay < maximumDelay - delay else { return maximumDelay }
            delay *= 2
            doublings -= 1
        }
        return delay
    }
}
