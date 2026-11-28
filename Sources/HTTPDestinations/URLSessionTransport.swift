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
    /// - Returns: The response the server sent, of any status, and its body.
    ///
    /// On Linux, cancelling the calling task returns at once and leaves the upload to finish on its
    /// own, unread, as FoundationNetworking can't cancel one safely.
    ///
    /// - Throws: ``HTTPTransportError/cancelled`` when the calling task was cancelled;
    ///   ``HTTPTransportError/invalidRequest(reason:)`` when the session can never send the
    ///   request (`URLError` `badURL`, `unsupportedURL` or
    ///   `appTransportSecurityRequiresSecureConnection`); otherwise
    ///   ``HTTPTransportError/failed(reason:)`` when no response arrived. Each reason is the
    ///   session error's domain and code, never the request's URL.
    public func send(_ request: HTTPRequest, body: Data) async throws(HTTPTransportError) -> HTTPTransportResponse {
        do {
            #if canImport(FoundationNetworking)
                return try await session.uploadWithoutCancelling(for: request, from: body)
            #else
                let (responseBody, head) = try await session.upload(for: request, from: body)
                return HTTPTransportResponse(head: head, body: responseBody)
            #endif
        } catch {
            // URLSession reports a cancelled task as URLError(.cancelled), not as a
            // CancellationError, so the task's own state decides.
            if Task.isCancelled || error is CancellationError {
                throw .cancelled
            }
            if let error = error as? URLError, error.code.meansInvalidRequest {
                throw .invalidRequest(reason: error.failureReason)
            }
            throw .failed(reason: error.failureReason)
        }
    }
}

extension URLError.Code {
    /// Whether the session can never send a request that failed with this code, however often
    /// it tries. Kept to these three: a TLS or certificate failure may pass once the device leaves
    /// a captive portal, so it stays a failure that is retried.
    fileprivate var meansInvalidRequest: Bool {
        self == .badURL || self == .unsupportedURL || self == .appTransportSecurityRequiresSecureConnection
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
