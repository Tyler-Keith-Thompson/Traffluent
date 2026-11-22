public import Hummingbird

/// The server example's routes, each response tracked as ``ExampleEvents/RequestServed`` through
/// `Tracker.current`.
///
/// - `GET /` answers a greeting.
/// - `GET /items/:id` answers the item's number, or 400 Bad Request when `id` isn't one.
///
/// - Returns: A router for an `Application`.
public func buildRouter() -> Router<BasicRequestContext> {
    let router = Router()
    router.add(middleware: RequestTrackingMiddleware())
    router.get("/") { _, _ in
        "Hello from Traffluent"
    }
    router.get("/items/:id") { _, context in
        let id = try context.parameters.require("id", as: Int.self)
        return "Item \(id)"
    }
    return router
}
