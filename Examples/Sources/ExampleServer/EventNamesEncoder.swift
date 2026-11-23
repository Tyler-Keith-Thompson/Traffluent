public import Events
public import HTTPDestinations
import Foundation

/// Encodes a batch as its events' names, one per line, as plain text: the body `POST /batches`
/// accepts (``buildRouter(tracer:)``).
public struct EventNamesEncoder: BatchEncoder {
    /// An encoder of event names.
    public init() {}

    /// The names of `batch`'s events, oldest first, one per line.
    ///
    /// - Parameter batch: Records of tracked events, oldest first.
    /// - Returns: The names as UTF-8 `text/plain`.
    public func encode(_ batch: [EventRecord]) -> EncodedBatch {
        EncodedBatch(body: Data(batch.map(\.name).joined(separator: "\n").utf8), contentType: "text/plain")
    }
}
