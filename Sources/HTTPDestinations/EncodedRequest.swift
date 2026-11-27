public import Foundation

/// One request of a batch as a ``BatchEncoder`` splits it: its body, and the records it carries.
///
/// ``HTTPDestination`` sends each request of a batch on its own, retries it on its own, and
/// reports the records of `recordIDs` when it drops it.
public struct EncodedRequest: Sendable, Hashable {
    /// The request's body and content type.
    public var body: EncodedBatch
    /// The `EventRecord.id` of each record the body holds, oldest first.
    public var recordIDs: [UUID]

    /// A request of `body`, carrying the records identified by `recordIDs`.
    ///
    /// - Parameters:
    ///   - body: The request's body and content type.
    ///   - recordIDs: The identifier of each record the body holds, oldest first.
    public init(body: EncodedBatch, recordIDs: [UUID]) {
        self.body = body
        self.recordIDs = recordIDs
    }
}
