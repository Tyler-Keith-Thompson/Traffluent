public import Foundation
public import Instrumentation

/// The `ServiceContext` key of the session an event was tracked in: a random identifier that
/// `Enricher.sessions(timeout:kinds:)` (module `Sessions`) sets on every record's context.
///
/// A destination reads it from each record's context:
///
/// ```swift
/// let session = record.context[SessionKey.self]  // a UUID
/// ```
///
/// The identifier is a version 7 UUID: its first 48 bits are the session's start, the timestamp
/// of its first record, in Unix milliseconds, and the other 74 bits that aren't the version and
/// variant are random, never derived from the device, the user or another identifier. The
/// enricher keeps it in memory only, so a new tracker, as on the next launch, starts a new session
/// with a new identifier.
///
/// A store keeps it beside each record of the session, as part of the record's own bytes, and it
/// is deleted when the store deletes the record's bytes (a `SegmentStore`: once its whole segment
/// is delivered). So a record recovered after a relaunch carries the session it was tracked in,
/// and a destination sends it under the same identifier as before. It is the only part of a record's context a store keeps, and a store never keeps
/// it apart from a record.
public enum SessionKey: ServiceContextKey {
    /// The session's identifier.
    public typealias Value = UUID
}
