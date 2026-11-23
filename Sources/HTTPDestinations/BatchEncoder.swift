public import Events

/// What turns a batch of records into the body of the request ``HTTPDestination`` sends.
///
/// Events need no `Codable` conformance: an encoder reads the events it knows by casting each
/// record's `EventRecord.event` to their types, and chooses the wire format and its content type.
/// An encoder for a server that deduplicates writes each record's `EventRecord.id`, which a
/// redelivered record keeps.
///
/// ```swift
/// struct PlansEncoder: BatchEncoder {
///     func encode(_ batch: [EventRecord]) -> EncodedBatch {
///         let plans = batch.compactMap { ($0.event as? SignedUp)?.plan }
///         return EncodedBatch(body: Data(plans.joined(separator: "\n").utf8), contentType: "text/plain")
///     }
/// }
/// ```
public protocol BatchEncoder: Sendable {
    /// What ``encode(_:)`` throws; `Never` for an encoder that can't fail.
    associatedtype Failure: Error = Never

    /// The request body for `batch`.
    ///
    /// - Parameter batch: Records of tracked events, oldest first; never empty.
    /// - Returns: The body's bytes and their content type.
    /// - Throws: `Failure` when the batch can't be encoded; ``HTTPDestination`` then sends nothing
    ///   for it.
    func encode(_ batch: [EventRecord]) throws(Failure) -> EncodedBatch
}
