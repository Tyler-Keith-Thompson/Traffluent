public import Foundation
public import HTTPTypes

/// What sends an HTTP request and returns the server's response: the seam between
/// ``HTTPDestination`` and the network.
///
/// A transport knows nothing of events. It sends the request and its body as given, and returns
/// whatever response arrives, whatever its status; deciding what a status means is its caller's
/// job. ``URLSessionTransport`` is the default; conform another type to send through a client of
/// your own (AsyncHTTPClient, a test double).
public protocol HTTPTransport: Sendable {
    /// Sends `request` with `body` and returns the response.
    ///
    /// A transport honours cancellation: when the calling task is cancelled, it stops waiting for
    /// the response and throws ``HTTPTransportError/cancelled``.
    ///
    /// - Parameters:
    ///   - request: The method, URL and header fields to send.
    ///   - body: The request's body.
    /// - Returns: The response the server sent, of any status.
    /// - Throws: ``HTTPTransportError/cancelled`` when the calling task was cancelled, or
    ///   ``HTTPTransportError/failed(reason:)`` when no response arrived.
    func send(_ request: HTTPRequest, body: Data) async throws(HTTPTransportError) -> HTTPResponse
}
