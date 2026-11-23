public import Foundation
public import HTTPTypes
public import Instrumentation

extension HTTPDestination where Transport == URLSessionTransport {
    /// A destination that sends batches to `endpoint` with `URLSession.shared`, encoded by
    /// `encoder`.
    ///
    /// - Parameters:
    ///   - endpoint: The URL each batch is posted to.
    ///   - headerFields: The header fields every request carries (an `Authorization`, say);
    ///     none by default. The injected trace context replaces fields of its names, and the
    ///     encoder's content type replaces a `Content-Type`.
    ///   - instrument: What injects each batch's first record's trace context into the header
    ///     fields; the bootstrapped `InstrumentationSystem.instrument`, read once here, by
    ///     default.
    ///   - encoder: What turns each batch into a request body.
    public init(
        endpoint: URL,
        headerFields: HTTPFields = [:],
        instrument: any Instrument = InstrumentationSystem.instrument,
        encoder: Encoding
    ) {
        self.init(
            endpoint: endpoint,
            headerFields: headerFields,
            instrument: instrument,
            transport: URLSessionTransport(),
            encoder: encoder)
    }
}
