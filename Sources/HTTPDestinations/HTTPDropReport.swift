public import Foundation
public import HTTPTypes

/// A batch ``HTTPDestination`` dropped without delivering it, and why.
///
/// A destination reports every batch it drops for good on ``HTTPDestination/dropReports``: one
/// the endpoint rejected with a status that retrying won't change, one whose request the
/// transport can never send, one whose request was still undelivered at its deadline, or one
/// its encoder couldn't encode. It reports each record the encoder left out of a batch's requests
/// too. A batch whose send failed for a while and was then delivered isn't reported, and neither
/// is one whose delivery was cancelled. A dropped batch counts as received, so a store keeping its
/// records forgets them. A crash or a cancellation between a report and the batch's
/// acknowledgement leaves the store holding the batch, so after a relaunch the same record
/// identifiers can be reported again, as ``rejected(status:recordIDs:)`` or
/// ``deadlineExceeded(deadline:recordIDs:)``.
public enum HTTPDropReport<Failure: Error>: Sendable {
    /// The endpoint answered with `status`, a non-2xx status other than 408, 429 or 5xx, so the
    /// batch of the records identified by `recordIDs` (`EventRecord.id`), oldest first, was
    /// dropped.
    case rejected(status: HTTPResponse.Status, recordIDs: [UUID])
    /// The transport can never send the request (``HTTPTransportError/invalidRequest(reason:)``:
    /// a malformed or unsupported URL, or one the platform refuses), for the reason `reason`, so
    /// the batch of the records identified by `recordIDs`, oldest first, was dropped.
    case invalidRequest(reason: String, recordIDs: [UUID])
    /// The request wasn't delivered by `deadline` (``EncodedRequest/deadline``), the latest moment
    /// it could be sent, so the whole request was dropped rather than sent again: every record it
    /// holds, identified by `recordIDs` in the request's order, the younger ones whose own age
    /// was still within the vendor's window included. The batch's other requests are still
    /// sent.
    case deadlineExceeded(deadline: Date, recordIDs: [UUID])
    /// The encoder threw `error` for the batch of the records identified by `recordIDs`, oldest
    /// first, so nothing was sent and the batch was dropped.
    case notEncoded(Failure, recordIDs: [UUID])
    /// The encoder left the record out of the batch's requests (``BatchEncoder/requests(for:)``),
    /// so it was never sent: one it can't write, or one too large for any request the endpoint
    /// takes. The batch's other records were sent.
    case skipped(SkippedRecord<Failure>)
}

extension HTTPDropReport: Equatable where Failure: Equatable {}

extension HTTPDropReport: Hashable where Failure: Hashable {}
