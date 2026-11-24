/// How long ``HTTPDestination`` waits before each new attempt at a batch that wasn't delivered:
/// binary exponential backoff, each wait twice the one before, up to a maximum.
///
/// With the defaults, the waits are 1, 2, 4, 8, 16 and 32 seconds, then 60 seconds for every
/// retry after that:
///
/// ```swift
/// let backoff = ExponentialBackoff(initialDelay: .seconds(1), maximumDelay: .seconds(60))
/// ```
///
/// The waits have no jitter. Each device starts retrying when its own send fails, and its sends
/// come at moments set by its own batches, so devices don't retry in step; a fixed schedule also
/// keeps the waits the same from one run to the next.
public struct ExponentialBackoff: Sendable, Hashable {
    /// The wait before the first retry.
    public let initialDelay: Duration
    /// The longest wait, which every retry waits once doubling reaches it.
    public let maximumDelay: Duration

    /// A backoff that waits `initialDelay` before the first retry and doubles each wait after
    /// it, up to `maximumDelay`.
    ///
    /// - Parameters:
    ///   - initialDelay: The wait before the first retry; 1 second by default.
    ///   - maximumDelay: The longest wait; 60 seconds by default.
    /// - Precondition: `initialDelay` is positive and `maximumDelay` is at least `initialDelay`;
    ///   ``init(checkedInitialDelay:maximumDelay:)`` throws instead.
    public init(initialDelay: Duration = .seconds(1), maximumDelay: Duration = .seconds(60)) {
        precondition(initialDelay > .zero, "A backoff's initial delay must be positive, not \(initialDelay)")
        precondition(maximumDelay >= initialDelay, "A backoff's maximum delay, \(maximumDelay), can't be less than its initial delay, \(initialDelay)")
        self.initialDelay = initialDelay
        self.maximumDelay = maximumDelay
    }

    /// A backoff that waits `checkedInitialDelay` before the first retry and doubles each wait
    /// after it, up to `maximumDelay`.
    ///
    /// - Parameters:
    ///   - checkedInitialDelay: The wait before the first retry.
    ///   - maximumDelay: The longest wait.
    /// - Throws: ``InvalidBackoff`` when `checkedInitialDelay` isn't positive or `maximumDelay`
    ///   is less than it.
    public init(checkedInitialDelay: Duration, maximumDelay: Duration) throws(InvalidBackoff) {
        guard checkedInitialDelay > .zero, maximumDelay >= checkedInitialDelay else { throw InvalidBackoff() }
        self.init(initialDelay: checkedInitialDelay, maximumDelay: maximumDelay)
    }

    /// The wait before retry number `retry`: `initialDelay` doubled `retry - 1` times, or
    /// `maximumDelay` if that is less.
    ///
    /// - Parameter retry: Which retry, counting from 1.
    /// - Returns: How long to wait before it.
    /// - Complexity: O(min(`retry`, log₂(`maximumDelay` / `initialDelay`))).
    /// - Precondition: `retry` is at least 1.
    public func delay(beforeRetry retry: Int) -> Duration {
        precondition(retry >= 1, "Retries count from 1, not \(retry)")
        var delay = initialDelay
        for _ in 1 ..< retry {
            // Whether twice the wait passes the maximum, asked of the difference: exact, where
            // `maximumDelay / 2` rounds down, and unable to overflow, as doubling first could.
            guard delay < maximumDelay - delay else { return maximumDelay }
            delay *= 2
        }
        return delay
    }
}
