/// A date that has no epoch-milliseconds or ISO 8601 timestamp: NaN, infinite, or further from
/// 1970 than `Int64.max` milliseconds (about 292 million years).
public struct UnrepresentableTimestamp: Error, Sendable, Hashable {
    /// The error.
    public init() {}
}
