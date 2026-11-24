public import Foundation

/// A record ``CollectorBatchEncoder`` left out of a batch's body, and why.
///
/// The encoder writes every other record of the batch, so one record the plan doesn't describe
/// costs only itself.
public struct SkippedRecord: Sendable, Hashable {
    /// The record's `EventRecord/id`.
    public var recordID: UUID
    /// The event's `Event/name`.
    public var eventName: String
    /// The event's `Event/schemaVersion`.
    public var schemaVersion: Int
    /// Why the record couldn't be encoded.
    public var reason: CollectorEncodingError

    /// A record of `recordID`, whose event is `eventName` at `schemaVersion`, left out for
    /// `reason`.
    ///
    /// - Parameters:
    ///   - recordID: The record's identifier.
    ///   - eventName: The event's name.
    ///   - schemaVersion: The event's schema version.
    ///   - reason: Why the record couldn't be encoded.
    public init(recordID: UUID, eventName: String, schemaVersion: Int, reason: CollectorEncodingError) {
        self.recordID = recordID
        self.eventName = eventName
        self.schemaVersion = schemaVersion
        self.reason = reason
    }
}
