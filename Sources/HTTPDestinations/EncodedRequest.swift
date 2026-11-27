public import Foundation

/// One request of a batch as a ``BatchEncoder`` splits it: its body, the records it carries, and
/// the latest moment it may be sent.
///
/// ``HTTPDestination`` sends each request of a batch on its own, retries it on its own, and
/// reports the records of `recordIDs` when it drops it.
public struct EncodedRequest: Sendable, Hashable {
    /// The request's body and content type.
    public var body: EncodedBatch
    /// The `EventRecord.id` of each record the body holds, oldest first.
    public var recordIDs: [UUID]
    /// The latest wall-clock time at which the request may be sent, or `nil` when it may be sent
    /// at any time.
    ///
    /// ``HTTPDestination`` reads its clock before every attempt, the first included, and sends the
    /// request only while that time is at or before the deadline. Once it has passed, the request
    /// isn't sent again: it is dropped and reported as
    /// ``HTTPDropReport/deadlineExceeded(deadline:recordIDs:)``. An encoder for a vendor that
    /// misdates or ignores an event older than some age, while still answering 2xx, sets it to its
    /// oldest record's time plus that age, so a request retried past it is reported rather than
    /// counted as delivered.
    public var deadline: Date?

    /// A request of `body`, carrying the records identified by `recordIDs`, to be sent no later
    /// than `deadline`.
    ///
    /// - Parameters:
    ///   - body: The request's body and content type.
    ///   - recordIDs: The identifier of each record the body holds, oldest first.
    ///   - deadline: The latest wall-clock time at which the request may be sent; `nil`, by
    ///     default, for none.
    public init(body: EncodedBatch, recordIDs: [UUID], deadline: Date? = nil) {
        self.body = body
        self.recordIDs = recordIDs
        self.deadline = deadline
    }
}
