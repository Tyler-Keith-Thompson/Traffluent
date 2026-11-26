public import Events

/// The server answered a request for `path` with `status`: the server's own event, which
/// `RequestTrackingMiddleware` tracks for every response.
public struct RequestServed: Event, Equatable {
    /// The request's path, without its query.
    public var path: String
    /// The response's HTTP status code.
    public var status: Int

    /// The event for a response with `status` to a request for `path`.
    ///
    /// - Parameters:
    ///   - path: The request's path, without its query.
    ///   - status: The response's HTTP status code.
    public init(path: String, status: Int) {
        self.path = path
        self.status = status
    }
}
