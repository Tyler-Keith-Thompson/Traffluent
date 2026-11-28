public import Events
import Sessions

extension EventRecord {
    /// The record's session, or the record itself when its context has none: the identity a vendor
    /// destination sends (D4).
    ///
    /// A record has no session when the tracker that made it has no `Enricher.sessions()`. A
    /// record a store recovered after a relaunch keeps the session it was tracked in, so it has
    /// the identity it was first sent with.
    public var pseudonymousIdentity: PseudonymousIdentity {
        guard let session = context[SessionKey.self] else { return .record(id) }
        return .session(session)
    }

    /// The record's identifier as a lowercase UUID string, the same each time the record is sent:
    /// the dedupe key a vendor drops a second copy of an event by (an insert ID, a message ID, an
    /// idempotency key).
    ///
    /// A record is sent again when a request's response is lost, and a store hands one over again
    /// after a relaunch (`EventRecord/isRedelivered`); either way it keeps its identifier.
    public var deduplicationID: String {
        id.uuidString.lowercased()
    }
}
