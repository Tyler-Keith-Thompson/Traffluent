public import Foundation
public import HTTPTypes

/// What an ``HTTPTransport`` received for a request: the response's status and header fields, and
/// its body.
public struct HTTPTransportResponse: Sendable, Hashable {
    /// The response's status and header fields.
    public var head: HTTPResponse
    /// The response's body, empty when the server sent none.
    public var body: Data

    /// A response of `head` and `body`.
    ///
    /// - Parameters:
    ///   - head: The response's status and header fields.
    ///   - body: The response's body, empty when the server sent none.
    public init(head: HTTPResponse, body: Data) {
        self.head = head
        self.body = body
    }
}
