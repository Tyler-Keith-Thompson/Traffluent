import Foundation

/// The sessions a sequence of record timestamps makes: a session goes on while each record comes
/// less than ``timeout`` after the one before it, and the first to come later starts a new one.
struct SessionTimeline: Sendable {
    /// The inactivity after which the next record starts a new session.
    let timeout: Duration
    /// The session going on; `nil` before the first record.
    private(set) var current: Session?

    /// A timeline with no session yet, whose sessions end after `timeout` of inactivity.
    init(timeout: Duration) {
        self.timeout = timeout
    }

    /// Moves the timeline to a record tracked at `timestamp`.
    ///
    /// A record at least ``timeout`` after the session's last ends it and starts a new one. A
    /// record stamped before the session's last, as a clock set back stamps one, belongs to the
    /// session and leaves its last activity where it was.
    ///
    /// - Parameters:
    ///   - timestamp: When the record was tracked.
    ///   - makeID: Makes a new session's identifier.
    /// - Returns: The session the record belongs to, and any session that started or ended.
    mutating func advance(to timestamp: Date, makingID makeID: () -> UUID) -> SessionTransition {
        guard var session = current else {
            let started = Session(id: makeID(), start: timestamp, lastActivity: timestamp)
            current = started
            return .started(started)
        }
        guard Duration.seconds(timestamp.timeIntervalSince(session.lastActivity)) < timeout else {
            let started = Session(id: makeID(), start: timestamp, lastActivity: timestamp)
            current = started
            return .rotated(ended: session, started: started)
        }
        session.lastActivity = max(session.lastActivity, timestamp)
        current = session
        return .continued(session)
    }
}
