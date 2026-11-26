public import Hummingbird
import Trackers

/// Middleware tracking ``RequestServed`` through `Tracker.current` for every
/// response the routes after it give, failures included.
///
/// Bind the tracker around the running server with `withTracker`: request handlers run in its
/// child tasks, so they read it.
public struct RequestTrackingMiddleware<Context: RequestContext>: RouterMiddleware {
    /// Middleware tracking through the task's bound tracker.
    public init() {}

    /// Answers `request` through `next`, then tracks the response's status, or the status the error
    /// it threw becomes (500 Internal Server Error for one that names none).
    public func handle(
        _ request: Request,
        context: Context,
        next: (Request, Context) async throws -> Response
    ) async throws -> Response {
        do {
            let response = try await next(request, context)
            Tracker.current.track(RequestServed(path: request.uri.path, status: response.status.code))
            return response
        } catch {
            let status = (error as? any HTTPResponseError)?.status ?? .internalServerError
            Tracker.current.track(RequestServed(path: request.uri.path, status: status.code))
            throw error
        }
    }
}
