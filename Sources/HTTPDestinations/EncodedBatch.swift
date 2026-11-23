public import Foundation

/// A batch encoded as a request body: its bytes, and the media type that says how to read them.
public struct EncodedBatch: Sendable, Hashable {
    /// The request body.
    public var body: Data
    /// The body's media type, sent as the request's `Content-Type`: `"application/json"`, say.
    public var contentType: String

    /// A body of `body`'s bytes, of media type `contentType`.
    ///
    /// - Parameters:
    ///   - body: The request body.
    ///   - contentType: The body's media type.
    public init(body: Data, contentType: String) {
        self.body = body
        self.contentType = contentType
    }
}
