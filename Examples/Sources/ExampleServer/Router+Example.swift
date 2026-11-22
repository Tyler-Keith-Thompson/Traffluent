public import Hummingbird
public import Pipelines

/// The server example's routes, each response tracked as ``ExampleEvents/RequestServed`` through
/// `pipeline`.
///
/// - `GET /` answers a greeting.
/// - `GET /items/:id` answers the item's number, or 400 Bad Request when `id` isn't one.
///
/// - Parameter pipeline: The pipeline every response is tracked through.
/// - Returns: A router for an `Application`.
public func buildRouter(pipeline: Pipeline) -> Router<BasicRequestContext> {
    let router = Router()
    router.add(middleware: RequestTrackingMiddleware(pipeline: pipeline))
    router.get("/") { _, _ in
        "Hello from Traffluent"
    }
    router.get("/items/:id") { _, context in
        let id = try context.parameters.require("id", as: Int.self)
        return "Item \(id)"
    }
    return router
}
