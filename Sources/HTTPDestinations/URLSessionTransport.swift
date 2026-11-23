// URLSession on Apple platforms, FoundationNetworking's on Linux. WASI has no URLSession, so the
// transport is left out there (HTTPTypesFoundation leaves out its URLSession calls the same way),
// and an app on WASI passes a transport of its own.
#if !os(WASI)
    public import Foundation
    public import HTTPTypes
    import HTTPTypesFoundation
    #if canImport(FoundationNetworking)
        public import FoundationNetworking
    #endif

    /// An ``HTTPTransport`` that sends each request with a `URLSession`; not available on WASI.
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
        ///   ``HTTPTransportError/failed(reason:)`` with the session's error when no response
        ///   arrived.
        public func send(_ request: HTTPRequest, body: Data) async throws(HTTPTransportError) -> HTTPResponse {
            do {
                return try await session.upload(for: request, from: body).1
            } catch {
                // URLSession reports a cancelled task as URLError(.cancelled), not as a
                // CancellationError, so the task's own state decides.
                if Task.isCancelled || error is CancellationError {
                    throw .cancelled
                }
                throw .failed(reason: String(describing: error))
            }
        }
    }
#endif
