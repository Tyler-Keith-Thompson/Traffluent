// URLSession on Apple platforms, FoundationNetworking's on Linux.
public import Foundation
public import HTTPTypes
import HTTPTypesFoundation
#if canImport(FoundationNetworking)
    public import FoundationNetworking
#endif

/// An ``HTTPTransport`` that sends each request with a `URLSession`.
public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    /// A transport that sends through `session`.
    ///
    /// - Parameter session: The session each request is uploaded with; `URLSession.shared` by
    ///   default.
    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Uploads `body` with `request` and returns the response.
    ///
    /// - Parameters:
    ///   - request: The method, URL and header fields to send.
    ///   - body: The request's body.
    /// - Returns: The response the server sent, of any status; its body is discarded.
    /// - Throws: ``HTTPTransportError/cancelled`` when the calling task was cancelled, or
    ///   ``HTTPTransportError/failed(reason:)`` with the session error's domain and code, never
    ///   the request's URL, when no response arrived.
    public func send(_ request: HTTPRequest, body: Data) async throws(HTTPTransportError) -> HTTPResponse {
        do {
            return try await session.upload(for: request, from: body).1
        } catch {
            // URLSession reports a cancelled task as URLError(.cancelled), not as a
            // CancellationError, so the task's own state decides.
            if Task.isCancelled || error is CancellationError {
                throw .cancelled
            }
            throw .failed(reason: error.failureReason)
        }
    }
}

extension Error {
    /// The error's domain and code, such as `NSURLErrorDomain -1004`.
    ///
    /// Not its description: a `URLError`'s holds the request's URL, with any key or tenant in its
    /// query or path, and `HTTPDestination` logs the reason. The code still says what failed.
    fileprivate var failureReason: String {
        let error = self as NSError
        return "\(error.domain) \(error.code)"
    }
}
