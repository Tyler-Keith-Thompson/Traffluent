public import Foundation

/// A record of a collector batch that ``CollectorBatchDecoder/batch(from:)`` couldn't read back,
/// and why.
public struct UndecodedRecord: Sendable, Hashable {
    /// The record's position in the body's `records` array, from 0.
    public var offset: Int
    /// The record's `id`, or `nil` when it has none that is a UUID string.
    public var recordID: UUID?
    /// The record's event `name`, or `nil` when it has none that is a string.
    public var eventName: String?
    /// Why the record couldn't be read.
    public var reason: CollectorDecodingError

    /// The report of the record at `offset`.
    ///
    /// - Parameters:
    ///   - offset: The record's position in the body's `records` array.
    ///   - recordID: The record's identifier, when it has one.
    ///   - eventName: The record's event name, when it has one.
    ///   - reason: Why the record couldn't be read.
    public init(offset: Int, recordID: UUID?, eventName: String?, reason: CollectorDecodingError) {
        self.offset = offset
        self.recordID = recordID
        self.eventName = eventName
        self.reason = reason
    }
}
