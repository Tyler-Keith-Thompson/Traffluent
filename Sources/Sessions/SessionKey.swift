public import Foundation
public import Instrumentation

/// The `ServiceContext` key of the session an event was tracked in: a random identifier that
/// `Enricher.sessions(timeout:kinds:)` sets on every record's context.
///
/// A destination reads it from each record's context:
///
/// ```swift
/// let session = record.context[SessionKey.self]  // a UUID
/// ```
///
/// The identifier is a version 7 UUID: its first 48 bits are the session's start, the timestamp
/// of its first record, in Unix milliseconds, and the other 74 bits that aren't the version and
/// variant are random, never derived from the device, the user or another identifier. It lives in the enricher's memory only, so it is never written to disk,
/// not even by a store, which keeps no record's context; a new tracker, as on the next launch,
/// starts a new session with a new identifier.
public enum SessionKey: ServiceContextKey {
    /// The session's identifier.
    public typealias Value = UUID
}
