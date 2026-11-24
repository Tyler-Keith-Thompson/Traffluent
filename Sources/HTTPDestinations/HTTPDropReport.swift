public import Foundation
public import HTTPTypes

/// A batch ``HTTPDestination`` dropped without delivering it, and why.
///
/// A destination reports every batch it drops for good on ``HTTPDestination/dropReports``: one
/// the endpoint rejected with a status that retrying won't change, one whose request the
/// transport can never send, or one its encoder couldn't encode. A batch whose send failed for a while and was then delivered isn't reported, and
/// neither is one whose delivery was cancelled. A dropped batch counts as received, so a store
/// keeping its records forgets them.
public enum HTTPDropReport<Failure: Error>: Sendable {
    /// The endpoint answered with `status`, a non-2xx status other than 408, 429 or 5xx, so the
    /// batch of the records identified by `recordIDs` (`EventRecord.id`), oldest first, was
    /// dropped.
    case rejected(status: HTTPResponse.Status, recordIDs: [UUID])
    /// The transport can never send the request (``HTTPTransportError/invalidRequest(reason:)``:
    /// a malformed or unsupported URL, or one the platform refuses), for the reason `reason`, so
    /// the batch of the records identified by `recordIDs`, oldest first, was dropped.
    case invalidRequest(reason: String, recordIDs: [UUID])
    /// The encoder threw `error` for the batch of the records identified by `recordIDs`, oldest
    /// first, so nothing was sent and the batch was dropped.
    case notEncoded(Failure, recordIDs: [UUID])
}

extension HTTPDropReport: Equatable where Failure: Equatable {}

extension HTTPDropReport: Hashable where Failure: Hashable {}
