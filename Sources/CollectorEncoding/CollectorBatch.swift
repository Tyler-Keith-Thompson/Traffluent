public import HTTPDestinations

/// A batch as ``CollectorBatchEncoder/batch(of:)`` encodes it: the body of the records it could
/// encode, and the records it left out.
public struct CollectorBatch: Sendable, Hashable {
    /// The request body, holding every record but the skipped ones, in the batch's order; `nil`
    /// when the batch had records and every one was skipped, so there is nothing to send.
    public var body: EncodedBatch?
    /// The records left out of `body`, in the batch's order.
    public var skippedRecords: [SkippedRecord]

    /// A batch of `body`, without `skippedRecords`.
    ///
    /// - Parameters:
    ///   - body: The request body, or `nil` when there is nothing to send.
    ///   - skippedRecords: The records left out of `body`.
    public init(body: EncodedBatch?, skippedRecords: [SkippedRecord]) {
        self.body = body
        self.skippedRecords = skippedRecords
    }
}
