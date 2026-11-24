import Foundation

extension Date {
    /// The date in ISO 8601, in UTC with milliseconds: `2026-11-23T14:03:27.512Z`.
    var collectorTimestamp: String {
        formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    }
}
