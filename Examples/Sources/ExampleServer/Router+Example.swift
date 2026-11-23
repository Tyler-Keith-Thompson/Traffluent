import Foundation
public import Hummingbird
public import Tracing

/// The server example's routes, each response tracked as ``ExampleEvents/RequestServed`` through
/// `Tracker.current`.
///
/// - `GET /` answers a greeting.
/// - `GET /items/:id` answers the item's number, or 400 Bad Request when `id` isn't one.
/// - `POST /batches` accepts a batch an app's `HTTPDestination` sends, encoded by
///   ``RecordLinesEncoder``, and answers 204 No Content, or 400 Bad Request when a line isn't a
///   record identifier and an event name. It extracts the trace context from the request's header
///   fields and handles the batch in a server span named `POST /batches`, a child of the app's
///   span, with a span event per record in the batch, named for its event, whose `record.id`
///   attribute is the record's identifier. So the server's trace and the app's events share a
///   trace ID, and a record sent twice shows up under one identifier.
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
            let lines = String(buffer: body).split(separator: "\n")
            let records = lines.compactMap(ReceivedRecord.init(line:))
            guard records.count == lines.count else {
                return Response(status: .badRequest)
            }
            for record in records {
                span.addEvent(SpanEvent(name: record.name, attributes: ["record.id": .string(record.id.uuidString)]))
            }
            return Response(status: .noContent)
        }
    }
    return router
}

/// A record line of a batch ``RecordLinesEncoder`` wrote.
private struct ReceivedRecord {
    let id: UUID
    let name: String

    /// The record `line` describes, or `nil` when it isn't a UUID, a space and a name.
    init?(line: Substring) {
        let parts = line.split(separator: " ", maxSplits: 1)
        guard parts.count == 2, let id = UUID(uuidString: String(parts[0])) else { return nil }
        self.id = id
        name = String(parts[1])
    }
}
