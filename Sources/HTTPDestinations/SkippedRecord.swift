public import Foundation

/// A record a ``BatchEncoder`` left out of a batch's requests, and why.
///
/// The encoder writes every other record of the batch, so one record it can't send costs only
/// itself. ``HTTPDestination`` logs each one and reports it on ``HTTPDestination/dropReports``
/// as ``HTTPDropReport/skipped(_:)``.
public struct SkippedRecord<Reason: Error>: Sendable {
    /// The record's `EventRecord/id`.
    public var recordID: UUID
    /// The event's `Event/name`.
    public var eventName: String
    /// The event's `Event/schemaVersion`.
    public var schemaVersion: Int
    /// Why the record couldn't be sent.
    public var reason: Reason

    /// A record of `recordID`, whose event is `eventName` at `schemaVersion`, left out for
    /// `reason`.
    ///
    /// - Parameters:
    ///   - recordID: The record's identifier.
    ///   - eventName: The event's name.
    ///   - schemaVersion: The event's schema version.
    ///   - reason: Why the record couldn't be sent.
    public init(recordID: UUID, eventName: String, schemaVersion: Int, reason: Reason) {
        self.recordID = recordID
        self.eventName = eventName
        self.schemaVersion = schemaVersion
        self.reason = reason
    }
}

extension SkippedRecord: Equatable where Reason: Equatable {}

extension SkippedRecord: Hashable where Reason: Hashable {}
