/// The error ``ExponentialBackoff/init(initialDelay:maximumDelay:jitter:)`` throws for an
/// initial delay that isn't positive, or a maximum delay less than it.
public struct InvalidBackoff: Error, Hashable, Sendable {
    /// The error.
    public init() {}
}
