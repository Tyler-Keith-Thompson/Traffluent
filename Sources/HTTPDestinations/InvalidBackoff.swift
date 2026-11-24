/// The error ``ExponentialBackoff/init(checkedInitialDelay:maximumDelay:)`` throws for an
/// initial delay that isn't positive, or a maximum delay less than it.
public struct InvalidBackoff: Error, Hashable, Sendable {
    /// The error.
    public init() {}
}
