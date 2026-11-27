/// How long ``HTTPDestination`` waits before each new attempt at a batch that wasn't delivered:
/// binary exponential backoff, each wait twice the one before, up to a maximum.
///
/// `ExponentialBackoff()` waits 1, 2, 4, 8, 16 and 32 seconds, then 60 seconds for every retry
/// after that, as this one does:
///
/// ```swift
/// let backoff = try ExponentialBackoff(initialDelay: .seconds(1), maximumDelay: .seconds(60))
/// ```
///
/// ``HTTPDestination`` sleeps exactly ``delay(beforeRetry:)`` before each retry when both delays
/// count their attoseconds in 53 significant bits or fewer, as any whole number of milliseconds
/// under 295 seconds does. Otherwise each wait it sleeps is within about one part in 2⁵³ of it.
///
/// The waits have no jitter. Each device starts retrying when its own send fails, and its sends
/// come at moments set by its own batches, so devices don't retry in step; a fixed schedule also
/// keeps the waits the same from one run to the next.
public struct ExponentialBackoff: Sendable, Hashable {
    /// The wait before the first retry.
    public let initialDelay: Duration
    /// The longest wait, which every retry waits once doubling reaches it.
    public let maximumDelay: Duration

    /// A backoff that waits 1 second before the first retry and doubles each wait after it, up
    /// to 60 seconds.
    public init() {
        initialDelay = .seconds(1)
        maximumDelay = .seconds(60)
    }

    /// A backoff that waits `initialDelay` before the first retry and doubles each wait after
    /// it, up to `maximumDelay`.
    ///
    /// - Parameters:
    ///   - initialDelay: The wait before the first retry.
    ///   - maximumDelay: The longest wait.
    /// - Throws: ``InvalidBackoff`` when `initialDelay` isn't positive or `maximumDelay` is less
    ///   than it.
    public init(initialDelay: Duration, maximumDelay: Duration) throws(InvalidBackoff) {
        guard initialDelay > .zero, maximumDelay >= initialDelay else { throw InvalidBackoff() }
        self.initialDelay = initialDelay
        self.maximumDelay = maximumDelay
    }

    /// The wait before retry number `retry`: `initialDelay` doubled `retry - 1` times, or
    /// `maximumDelay` if that is less.
    ///
    /// - Parameter retry: Which retry, counting from 1.
    /// - Returns: How long to wait before it.
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
