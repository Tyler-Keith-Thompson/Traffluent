import Foundation
public import Hummingbird
public import Tracing

/// The server example's routes, each response tracked as ``RequestServed`` through
/// `Tracker.current`.
///
/// - `GET /` answers a greeting.
/// - `GET /items/:id` answers the item's number, or 400 Bad Request when `id` isn't one.
/// - `POST /v1/batches` stands in for a TraffluentCollector: it accepts a batch an app's
///   `HTTPDestination` sends, encoded by `CollectorBatchEncoder`, logs each record's event name and
///   identifier, and answers 204 No Content, or 400 Bad Request when the body isn't a collector
///   batch. It extracts the trace context from the request's header fields and handles the batch
///   in a server span named `POST /v1/batches`, a child of the app's span, with a span event per
///   record in the batch, named for its event, whose `record.id` attribute is the record's
///   identifier. So the server's trace and the app's events share a trace ID, and a record sent
///   twice shows up under one identifier.
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
    router.post("/v1/batches") { request, context in
        var traceContext = ServiceContext.current ?? .topLevel
        tracer.extract(request.headers, into: &traceContext, using: HTTPFieldsExtractor())
        return try await tracer.withSpan("POST /v1/batches", context: traceContext, ofKind: .server) { span in
            let body = try await request.body.collect(upTo: context.maxUploadSize)
            guard let batch = try? JSONDecoder().decode(IngestedBatch.self, from: Data(buffer: body)) else {
                return Response(status: .badRequest)
            }
            for record in batch.records {
                context.logger.info("Received \(record.name) \(record.id)\(record.isRedelivered ? ", redelivered" : "")")
                span.addEvent(SpanEvent(name: record.name, attributes: ["record.id": .string(record.id.uuidString)]))
            }
            return Response(status: .noContent)
        }
    }
    return router
}
