public import Events
public import HTTPDestinations
import Foundation

/// Encodes a batch as one line per record, its identifier then its event's name, separated by a
/// space, as plain text: the body `POST /batches` accepts (``buildRouter(tracer:)``).
public struct RecordLinesEncoder: BatchEncoder {
    /// An encoder of record lines.
    public init() {}

    /// A line per record of `batch`, oldest first: `EventRecord.id`'s UUID string, a space, and
    /// `EventRecord.name`.
    ///
    /// - Parameter batch: Records of tracked events, oldest first.
    /// - Returns: The lines as UTF-8 `text/plain`.
    public func encode(_ batch: [EventRecord]) -> EncodedBatch {
        EncodedBatch(body: Data(batch.map { "\($0.id.uuidString) \($0.name)" }.joined(separator: "\n").utf8), contentType: "text/plain")
    }
}
