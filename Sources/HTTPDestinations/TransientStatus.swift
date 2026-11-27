public import HTTPTypes

/// A failure status that ``HTTPDestination`` retries, beside 408 Request Timeout, 429 Too Many
/// Requests and every 5xx, for an encoder that lists it in ``BatchEncoder/transientStatuses``.
///
/// A vendor whose server answers a status outside that set for a request that may be taken when
/// sent again names it here, such as Aptabase's 418 for a body that arrived too slowly:
///
/// ```swift
/// static let transientStatuses: Set<TransientStatus> = (try? TransientStatus(418)).map { [$0] } ?? []
/// ```
///
/// Only a failure can be one: a client error (4xx) or a server error (5xx). A 2xx is always
/// delivered, and a 1xx or 3xx, which ``HTTPDestination`` doesn't follow, is no failure a retry
/// would mend.
public struct TransientStatus: Sendable, Hashable {
    /// The status.
    public let status: HTTPResponse.Status

    /// The failure status `status`, for ``HTTPDestination`` to retry.
    ///
    /// - Parameter status: A client error (400 through 499) or server error (500 through 599).
    /// - Throws: ``InvalidTransientStatus`` for any other status.
    public init(_ status: HTTPResponse.Status) throws(InvalidTransientStatus) {
        // The kind, rather than a range of codes, as HTTPTypes classifies a status by its first
        // digit, the way RFC 9110 defines the classes.
        guard status.kind == .clientError || status.kind == .serverError else {
            throw InvalidTransientStatus()
        }
        self.status = status
    }
}
