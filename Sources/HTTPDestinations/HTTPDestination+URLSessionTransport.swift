public import Foundation
public import HTTPTypes
public import Instrumentation

extension HTTPDestination where Transport == URLSessionTransport {
    /// A destination that sends batches to `endpoint` with `URLSession.shared`, encoded by
    /// `encoder`, retrying a send that fails for now with the waits of `backoff` on `clock`.
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
    ///   - backoff: How long to wait before each new attempt at a batch; 1 second, doubling up
    ///     to 60 seconds, with full jitter, by default.
    ///   - clock: The clock the waits are measured on.
    ///   - randomNumberGenerator: The source of the backoff's jitter, which this destination, its
    ///     copies and every request they retry draw from in turn; the system's generator by
    ///     default. Pass a seeded generator in tests only, as the designated initializer says.
    ///   - now: The wall-clock time, read before each attempt at a request with a deadline
    ///     (``EncodedRequest/deadline``); the system's clock by default.
    public init(
        endpoint: URL,
        headerFields: HTTPFields = [:],
        instrument: any Instrument = InstrumentationSystem.instrument,
        encoder: Encoding,
        backoff: ExponentialBackoff = ExponentialBackoff(),
        clock: some Clock<Duration> = ContinuousClock(),
        randomNumberGenerator: some RandomNumberGenerator & Sendable = SystemRandomNumberGenerator(),
        now: @escaping @Sendable () -> Date = { Date.now }
    ) {
        self.init(
            endpoint: endpoint,
            headerFields: headerFields,
            instrument: instrument,
            transport: URLSessionTransport(),
            encoder: encoder,
            backoff: backoff,
            clock: clock,
            randomNumberGenerator: randomNumberGenerator,
            now: now)
    }
}
