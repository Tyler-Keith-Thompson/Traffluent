public import Foundation

extension Date {
    /// The date in ISO 8601, in UTC with milliseconds, rounded down: `2026-11-23T14:03:27.512Z`.
    ///
    /// The form a `Date` property is written in, and the timestamp most JSON ingestion APIs take.
    public var iso8601Timestamp: String {
        formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    }

    /// The milliseconds from 1970-01-01T00:00:00Z to the date, rounded down, as
    /// ``iso8601Timestamp`` rounds: an epoch-milliseconds timestamp.
    ///
    /// - Returns: The whole milliseconds since 1970, negative before it.
    /// - Throws: ``UnrepresentableTimestamp`` when the date isn't finite, or is more than
    ///   `Int64.max` milliseconds from 1970 either way.
    public func millisecondsSince1970() throws(UnrepresentableTimestamp) -> Int64 {
        // Int64(exactly:) of the rounded-down value: nil for NaN, an infinity and anything outside
        // Int64's range, where Int64(_:) would trap.
        guard let milliseconds = Int64(exactly: (timeIntervalSince1970 * 1000).rounded(.down)) else {
            throw UnrepresentableTimestamp()
        }
        return milliseconds
    }
}
