/// Why an ``HTTPTransport`` returned no response.
public enum HTTPTransportError: Error, Sendable, Hashable {
    /// The calling task was cancelled before a response arrived.
    case cancelled
    /// No response arrived, for a reason a later attempt may not meet: no network, a refused
    /// connection or a timeout.
    ///
    /// - Parameter reason: What went wrong, for the developer reading the logs.
    case failed(reason: String)
    /// The transport can never send the request as it is: its URL is malformed or of a scheme the
    /// transport doesn't support, or the platform refuses it, as App Transport Security refuses
    /// an `http` URL.
    ///
    /// - Parameter reason: What went wrong, for the developer reading the logs.
    case invalidRequest(reason: String)
}
