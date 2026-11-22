public import Events

/// Where a pipeline delivers events: a plain sink that records the batches it receives.
///
/// A pipeline delivers each batch to every destination, and the next batch only once every
/// destination has returned from this one, so a destination sees its batches in the order the
/// events were tracked.
public protocol Destination: Sendable {
    /// Records `batch`.
    ///
    /// - Parameter batch: Records of tracked events, oldest first; never empty.
    func receive(_ batch: [EventRecord]) async
}
