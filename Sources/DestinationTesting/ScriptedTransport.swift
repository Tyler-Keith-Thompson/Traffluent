public import Foundation
public import HTTPDestinations
public import HTTPTypes
import Synchronization

/// An `HTTPTransport` that answers each request from a script and keeps every request it is
/// sent: the seam a ``DestinationConformance`` check sends through instead of the network.
///
/// The nth request gets the script's nth answer, and every request past its end gets its last.
/// Copies of a transport share its requests, and their count, so the destination's copy and the
/// test's see the same ones.
///
/// ```swift
/// let transport = ScriptedTransport([.status(.serviceUnavailable), .status(.ok)])
/// ```
public struct ScriptedTransport: HTTPTransport {
    /// What the transport answers one request with.
    public enum Answer: Sendable, Hashable {
        /// A response of this status.
        case status(HTTPResponse.Status)
        /// No response, as when the network is down: `HTTPTransportError/failed(reason:)`.
        case noResponse
    }

    /// A request the transport was sent.
    public struct SentRequest: Sendable, Hashable {
        /// The method, URL and header fields.
        public var request: HTTPRequest
        /// The body.
        public var body: Data
    }

    private let script: [Answer]
    // A class holding a Mutex, as the destination keeps its own copy of the transport and the
    // test reads what it sent: the box is what the copies share. A Mutex rather than an actor,
    // so `requests` reads without an `await`.
    private let sent = Box()

    /// A transport that answers with `script`, in order, then with its last answer for ever; 200
    /// for every request when it is empty.
    ///
    /// - Parameter script: The answers, the first for the first request.
    public init(_ script: [Answer]) {
        self.script = script
    }

    /// Every request the transport was sent, in order.
    public var requests: [SentRequest] {
        sent.requests.withLock { $0 }
    }

    /// Keeps `request` and `body`, and answers with the script's next answer.
    ///
    /// - Parameters:
    ///   - request: The method, URL and header fields to send.
    ///   - body: The request's body.
    /// - Returns: A response of the scripted status.
    /// - Throws: `HTTPTransportError.failed(reason:)` for a scripted ``Answer/noResponse``.
    public func send(_ request: HTTPRequest, body: Data) async throws(HTTPTransportError) -> HTTPResponse {
        let attempt = sent.requests.withLock { sent in
            sent.append(SentRequest(request: request, body: body))
            return sent.count
        }
        switch script.isEmpty ? .status(.ok) : script[min(attempt, script.count) - 1] {
        case .status(let status):
            return HTTPResponse(status: status)
        case .noResponse:
            throw .failed(reason: "scripted: no response")
        }
    }
}

extension ScriptedTransport {
    /// The requests every copy of one transport was sent.
    private final class Box: Sendable {
        let requests = Mutex<[SentRequest]>([])
    }
}
