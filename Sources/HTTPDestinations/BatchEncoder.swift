public import Events

/// What turns a batch of records into the requests ``HTTPDestination`` sends.
///
/// Events need no `Codable` conformance: an encoder reads the events it knows by casting each
/// record's `EventRecord.event` to their types, and chooses the wire format and its content type.
/// An encoder for a server that deduplicates writes each record's `EventRecord.id`, which a
/// redelivered record keeps.
///
/// An encoder for an endpoint without limits returns one request carrying every record:
///
/// ```swift
/// struct PlansEncoder: BatchEncoder {
///     func requests(for batch: [EventRecord]) -> BatchRequests<Never> {
///         let plans = batch.compactMap { ($0.event as? SignedUp)?.plan }
///         let body = EncodedBatch(body: Data(plans.joined(separator: "\n").utf8), contentType: "text/plain")
///         return BatchRequests(requests: [EncodedRequest(body: body, recordIDs: batch.map(\.id))], skippedRecords: [])
///     }
/// }
/// ```
///
/// An encoder for an endpoint that limits each request, by its size or its count of events,
/// splits the batch into requests the endpoint takes, and leaves out a record that fits in none
/// of them, or that it can't encode, as a ``SkippedRecord``. One whose ``requests(for:)`` doesn't
/// throw names its reasons' type as ``Failure`` (`typealias Failure = VendorEncodingError`), which
/// a method that doesn't throw leaves Swift unable to infer.
public protocol BatchEncoder: Sendable {
    /// What ``requests(for:)`` throws, and why a record was left out; `Never` for an encoder that
    /// can't fail.
    associatedtype Failure: Error

    /// The requests that carry `batch`, which ``HTTPDestination`` sends one after another, and the
    /// records left out of them.
    ///
    /// Each request's `recordIDs` are the records its body holds: ``HTTPDestination`` reports
    /// those when it drops the request.
    ///
    /// - Parameter batch: Records of tracked events, oldest first; never empty.
    /// - Returns: The requests, in the order they are sent, and each record left out, with why.
    /// - Throws: `Failure` when nothing of the batch can be encoded; ``HTTPDestination`` then
    ///   sends nothing for it and reports every record as one drop.
    func requests(for batch: [EventRecord]) throws(Failure) -> BatchRequests<Failure>
}
