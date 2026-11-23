public import Afluent
public import Events

/// A batch strategy that flushes as a delivery reads an ``ApplicationBackgrounded`` or
/// ``ApplicationTerminated`` record, so what is pending goes out as the app leaves the foreground
/// rather than waiting for its count or time.
///
/// Combine it with the others:
///
/// ```swift
/// let delivery = tracker.records
///     .batch(strategy: .either(.count(20), .time(interval: .seconds(30), clock: ContinuousClock()), .lifecycle))
///     .deliver(to: backend)
/// ```
///
/// The record itself marks the flush, rather than a signal sent beside the records, so the batch
/// it ends holds every record tracked before it. With ``LifecycleObservation/Kind/backgrounded``
/// turned off, or its consent category undecided or denied, there is no such record, and pending
/// records wait for the other strategies; the store, if any, still keeps them.
public struct LifecycleBatchStrategy: BatchStrategy {
    public typealias Element = EventRecord

    /// The strategy.
    public init() {}

    /// Whether the last of `pending` is the app leaving the foreground.
    ///
    /// - Parameter pending: The records waiting, oldest first.
    /// - Returns: `true` when the last is an ``ApplicationBackgrounded`` or
    ///   ``ApplicationTerminated`` record.
    public func flushes(pending: [EventRecord]) -> Bool {
        guard let event = pending.last?.event else { return false }
        return event is ApplicationBackgrounded || event is ApplicationTerminated
    }
}

extension BatchStrategy where Self == LifecycleBatchStrategy {
    /// Flushes as a delivery reads an ``ApplicationBackgrounded`` or ``ApplicationTerminated``
    /// record: a ``LifecycleBatchStrategy``.
    public static var lifecycle: LifecycleBatchStrategy {
        LifecycleBatchStrategy()
    }
}
