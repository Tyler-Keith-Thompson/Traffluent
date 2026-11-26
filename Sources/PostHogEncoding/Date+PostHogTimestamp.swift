import Foundation

// The same line as CollectorEncoding's timestamp, written again rather than shared: the two wire
// formats only happen to agree, and either may change alone.
extension Date {
    /// The date in ISO 8601, in UTC with milliseconds: `2026-11-23T14:03:27.512Z`.
    var postHogTimestamp: String {
        formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    }
}
