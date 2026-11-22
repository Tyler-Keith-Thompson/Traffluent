public import Afluent
public import Events

extension AsyncSequence where Self: Sendable, Element == EventRecord {
    /// Gathers the records into batches of 20, and every 30 seconds by `clock` while any are
    /// pending.
    ///
    /// The default for a delivery, short for Afluent's
    /// `batch(strategy: .either(.count(20), .time(interval: .seconds(30), clock: clock)))`. Pass a
    /// strategy of your own to `batch(strategy:)` for others.
    ///
    /// - Parameter clock: The clock the 30 seconds are measured on.
    /// - Returns: The records, in order, in batches of one or more; when the records end, what is
    ///   pending is the last batch.
    public func batch(
        clock: some Clock<Duration> = ContinuousClock()
    ) -> AsyncSequences.Batch<Self, EitherBatchStrategy<EventRecord>> {
        batch(strategy: EitherBatchStrategy(.count(20), .time(interval: .seconds(30), clock: clock)))
    }
}
