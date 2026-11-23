/// A kind of session event: pass the ones to track as `Enricher.sessions(timeout:kinds:)`'s
/// `kinds`.
public enum SessionEventKind: CaseIterable, Hashable, Sendable {
    /// ``SessionStarted``, before the first event of each session.
    case started
    /// ``SessionEnded``, when an event comes after the timeout, before the next session's start.
    case ended
}
