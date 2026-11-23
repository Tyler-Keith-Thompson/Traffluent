/// What a record's timestamp did to the sessions: the session it belongs to, and whether one
/// started or ended on its way there.
enum SessionTransition: Hashable, Sendable {
    /// The record belongs to the session already going.
    case continued(Session)
    /// The record is the first the enricher has seen, and starts the first session.
    case started(Session)
    /// The record came after the timeout: `ended` ended with the event before it, and the record
    /// starts `started`.
    case rotated(ended: Session, started: Session)
}
