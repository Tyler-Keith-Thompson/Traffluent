/// The error `deliver(to:batchBufferLimit:bufferDropReporter:)` throws for a batch buffer limit
/// below 1.
public struct InvalidBatchBufferLimit: Error, Hashable, Sendable {
    /// The error.
    public init() {}
}
