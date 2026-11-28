public import Foundation

/// Who a record's event is attributed to, by the only identifiers Traffluent has: the record's
/// session, or, for a record with none, the record itself.
///
/// Neither identifies a person. A session's key is random, replaced with each new session, and
/// kept on disk only beside its own records, deleted with their bytes; a record's identifier is
/// random and names one event. A vendor that requires an identity on every event (a
/// `distinct_id`, a `device_id`, an `anonymousId`) is sent ``uuid``, so a record a store
/// recovered after a relaunch goes out under the session it was first sent with, and a record
/// tracked without a session becomes an anonymous visitor of one event, linked to nothing,
/// rather than being left out.
public enum PseudonymousIdentity: Sendable, Hashable {
    /// The record's session, its `SessionKey`.
    case session(UUID)
    /// The record's own `EventRecord/id`, for a record whose context has no session.
    case record(UUID)

    /// The session's key, or the record's identifier.
    public var uuid: UUID {
        switch self {
        case .session(let uuid), .record(let uuid): uuid
        }
    }
}
