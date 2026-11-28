import Events
import Foundation
import Instrumentation
import Synchronization

/// The state behind `Enricher.sessions`: the timeline of one tracker's sessions, which stamps each
/// record with its session and makes the records of the sessions that start and end before it.
///
/// Held in memory only, so the next process starts a session of its own. A store keeps a
/// session's identifier only beside each of its records, until it deletes the record's bytes.
final class SessionRotation: Sendable {
    let kinds: Set<SessionEventKind>
    let callSite: SourceLocation
    // A Mutex rather than an actor: a tracker's worker calls its enrichers synchronously, so it
    // can't await one. The worker is the only caller, one record at a time, so the lock is never
    // contended; it is there because the enricher must be Sendable, and an app may hand one to
    // two trackers, whose workers then share its sessions.
    private let timeline: Mutex<SessionTimeline>

    init(timeout: Duration, kinds: Set<SessionEventKind>, callSite: SourceLocation) {
        self.kinds = kinds
        self.callSite = callSite
        timeline = Mutex(SessionTimeline(timeout: timeout))
    }

    /// Sets `record`'s session on its context, and returns the records of the sessions that
    /// ended and started at it, which go before it.
    func enrich(_ record: inout EventRecord) -> [EventRecord] {
        let timestamp = record.timestamp
        let transition = timeline.withLock { $0.advance(to: timestamp, makingID: { UUID(version7At: timestamp) }) }
        let context = record.context
        switch transition {
        case .continued(let session):
            record.context[SessionKey.self] = session.id
            return []
        case .started(let session):
            record.context[SessionKey.self] = session.id
            return kinds.contains(.started) ? [startRecord(of: session, in: context)] : []
        case .rotated(let ended, let started):
            record.context[SessionKey.self] = started.id
            var records: [EventRecord] = []
            if kinds.contains(.ended) {
                records.append(endRecord(of: ended, in: context))
            }
            if kinds.contains(.started) {
                records.append(startRecord(of: started, in: context))
            }
            return records
        }
    }
}

extension SessionRotation {
    /// The ``SessionStarted`` record of `session`, at its first event's time.
    fileprivate func startRecord(of session: Session, in context: ServiceContext) -> EventRecord {
        var context = context
        context[SessionKey.self] = session.id
        return EventRecord(event: SessionStarted(), timestamp: session.start, sourceLocation: callSite, context: context)
    }

    /// The ``SessionEnded`` record of `session`, at its last event's time.
    fileprivate func endRecord(of session: Session, in context: ServiceContext) -> EventRecord {
        var context = context
        context[SessionKey.self] = session.id
        return EventRecord(event: SessionEnded(duration: session.duration), timestamp: session.lastActivity, sourceLocation: callSite, context: context)
    }
}
