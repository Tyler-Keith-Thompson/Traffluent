/// Why an ``HTTPTransport`` returned no response.
public enum HTTPTransportError: Error, Sendable, Hashable {
    /// The calling task was cancelled before a response arrived.
    case cancelled
    /// No response arrived: no network, a refused connection, a timeout or a malformed request.
    ///
    /// - Parameter reason: What went wrong, for the developer reading the logs.
    case failed(reason: String)
}
