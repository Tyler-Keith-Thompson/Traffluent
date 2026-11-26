import Foundation
import HTTPDestinations
import HTTPTypes

/// A transport that prints each request's body, the JSON a collector would receive, and answers
/// 204 No Content without sending anything.
struct PrintingTransport: HTTPTransport {
    func send(_ request: HTTPRequest, body: Data) async throws(HTTPTransportError) -> HTTPResponse {
        print(String(decoding: body, as: UTF8.self))
        return HTTPResponse(status: .noContent)
    }
}
