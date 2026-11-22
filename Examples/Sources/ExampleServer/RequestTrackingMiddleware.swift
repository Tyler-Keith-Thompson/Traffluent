public import Hummingbird
public import Pipelines
import ExampleEvents

/// Middleware tracking ``ExampleEvents/RequestServed`` for every response the routes after it
/// give, failures included.
public struct RequestTrackingMiddleware<Context: RequestContext>: RouterMiddleware {
    private let pipeline: Pipeline

    /// Middleware tracking through `pipeline`.
    ///
    /// - Parameter pipeline: The pipeline every response is tracked through.
    public init(pipeline: Pipeline) {
        self.pipeline = pipeline
    }

    /// Answers `request` through `next`, then tracks the response's status, or the status the error
    /// it threw becomes (500 Internal Server Error for one that names none).
    public func handle(
        _ request: Request,
        context: Context,
        next: (Request, Context) async throws -> Response
    ) async throws -> Response {
        do {
            let response = try await next(request, context)
            await pipeline.track(RequestServed(path: request.uri.path, status: response.status.code))
            return response
        } catch {
            let status = (error as? any HTTPResponseError)?.status ?? .internalServerError
            await pipeline.track(RequestServed(path: request.uri.path, status: status.code))
            throw error
        }
    }
}
