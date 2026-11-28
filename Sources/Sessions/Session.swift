import Foundation

/// A session as the enricher knows it: its identifier, and the times of its first and last events.
struct Session: Hashable, Sendable {
    /// The identifier every record of the session carries as its ``/Events/SessionKey``.
    let id: UUID
    /// When the session's first event was tracked.
    let start: Date
    /// When the session's latest event was tracked.
    var lastActivity: Date

    /// The time from the session's first event to its last.
    var duration: Duration {
        .seconds(lastActivity.timeIntervalSince(start))
    }
}
