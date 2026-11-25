import Events
import Synchronization

/// The event types a store was given records of without being given them in `events`, so each
/// is reported once as `DropReport.notPersisted(event:)`.
// A class around a Mutex, shared by every append; the lock is taken only for a record of an
// unlisted type, which a store isn't expected to see often.
package final class UnlistedEventTypes: Sendable {
    private let seen = Mutex<Set<ObjectIdentifier>>([])

    package init() {}

    /// Whether `type` is seen here for the first time; `false` on every later call for it.
    package func insert(_ type: any Event.Type) -> Bool {
        seen.withLock { $0.insert(ObjectIdentifier(type)).inserted }
    }
}
