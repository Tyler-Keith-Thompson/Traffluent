import HTTPTypes
import Instrumentation

/// Reads the trace context an instrument extracts from a request's header fields.
///
/// Hummingbird's `TracingMiddleware` has an extractor of its own, but it reads the process-wide
/// `InstrumentationSystem`, which a test can bootstrap only once per process; the batches route
/// takes its tracer as a parameter instead, so it extracts with this one.
struct HTTPFieldsExtractor: Extractor {
    func extract(key: String, from fields: HTTPFields) -> String? {
        HTTPField.Name(key).flatMap { fields[$0] }
    }
}
