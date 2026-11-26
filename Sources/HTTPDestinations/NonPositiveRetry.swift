/// The error ``ExponentialBackoff/delay(beforeRetry:)`` throws for a retry numbered below 1.
public struct NonPositiveRetry: Error, Hashable, Sendable {
    /// The error.
    public init() {}
}
