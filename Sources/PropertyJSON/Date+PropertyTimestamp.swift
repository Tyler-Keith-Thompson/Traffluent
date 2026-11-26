import Foundation

extension Date {
    /// The date in ISO 8601, in UTC with milliseconds: `2026-11-23T14:03:27.512Z`, as a `Date`
    /// property is written.
    var propertyTimestamp: String {
        formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    }
}
