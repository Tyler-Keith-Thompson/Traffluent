public import Events

/// Where a delivery sends events: a plain sink that records the batches it receives.
///
/// `deliver(to:batchBufferLimit:)` gives each destination its batches in the order the events
/// were tracked, one at a time: the next batch comes once ``receive(_:)`` returns. Batches that
/// arrive meanwhile wait in a buffer of the destination's own, which drops its oldest batch when
/// full, so a destination that falls behind loses batches rather than holding up the others.
///
/// ``receive(_:)`` should return promptly and honour cancellation: a delivery waits for it
/// before it completes, and cancels it when the delivery is cancelled. A destination handles its
/// own errors (a failed upload, say); the delivery has none to receive.
///
/// When a tracker keeps its records in a store, returning from ``receive(_:)`` is what tells the
/// store a batch arrived: once every destination has returned for it, uncancelled, the store
/// forgets those records. A destination that buffers or retries should return only once the
/// batch is somewhere it won't be lost; a record whose `EventRecord.isRedelivered` is set may
/// have reached it in an earlier run.
public protocol Destination: Sendable {
    /// Records `batch`.
    ///
    /// - Parameter batch: Records of tracked events, oldest first; never empty.
    func receive(_ batch: [EventRecord]) async
}
