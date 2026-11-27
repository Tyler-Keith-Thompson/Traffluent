/// A batch as ``BatchEncoder/requests(for:)`` encodes it: the requests that carry its records, and
/// the records it left out.
public struct BatchRequests<Failure: Error>: Sendable {
    /// The requests, in the order they are sent, each holding records in the batch's order.
    public var requests: [EncodedRequest]
    /// The records left out of every request, in the batch's order.
    public var skippedRecords: [SkippedRecord<Failure>]

    /// The batch as `requests`, without `skippedRecords`.
    ///
    /// - Parameters:
    ///   - requests: The requests that carry the batch's records.
    ///   - skippedRecords: The records left out of them.
    public init(requests: [EncodedRequest], skippedRecords: [SkippedRecord<Failure>]) {
        self.requests = requests
        self.skippedRecords = skippedRecords
    }
}

extension BatchRequests: Equatable where Failure: Equatable {}

extension BatchRequests: Hashable where Failure: Hashable {}
