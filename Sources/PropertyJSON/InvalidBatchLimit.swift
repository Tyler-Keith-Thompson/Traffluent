/// A ``BatchLimit`` of fewer than 1 record or 1 byte, which no request could meet.
public struct InvalidBatchLimit: Error, Sendable, Hashable {
    /// The error.
    public init() {}
}
