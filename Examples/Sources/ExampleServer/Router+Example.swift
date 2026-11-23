public import Hummingbird
public import Tracing

/// The server example's routes, each response tracked as ``ExampleEvents/RequestServed`` through
/// `Tracker.current`.
///
/// - `GET /` answers a greeting.
/// - `GET /items/:id` answers the item's number, or 400 Bad Request when `id` isn't one.
/// - `POST /batches` accepts a batch an app's `HTTPDestination` sends, encoded by
///   ``EventNamesEncoder``, and answers 204 No Content. It extracts the trace context from the
///   request's header fields and handles the batch in a server span named `POST /batches`, a
///   child of the app's span, with a span event per event in the batch. So the server's trace
///   and the app's events share a trace ID.
///
/// - Parameter tracer: The tracer the batches route extracts the trace context with and records
///   its spans in; a `NoOpTracer` by default.
/// - Returns: A router for an `Application`.
public func buildRouter(tracer: some Tracer = NoOpTracer()) -> Router<BasicRequestContext> {
    let router = Router()
    router.add(middleware: RequestTrackingMiddleware())
    router.get("/") { _, _ in
        "Hello from Traffluent"
    }
    router.get("/items/:id") { _, context in
        let id = try context.parameters.require("id", as: Int.self)
        return "Item \(id)"
    }
    router.post("/batches") { request, context in
        var traceContext = ServiceContext.current ?? .topLevel
        tracer.extract(request.headers, into: &traceContext, using: HTTPFieldsExtractor())
        return try await tracer.withSpan("POST /batches", context: traceContext, ofKind: .server) { span in
            let body = try await request.body.collect(upTo: context.maxUploadSize)
            for name in String(buffer: body).split(separator: "\n") {
                span.addEvent(SpanEvent(name: String(name)))
            }
            return Response(status: .noContent)
        }
    }
    return router
}
