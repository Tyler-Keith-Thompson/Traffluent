import Afluent
public import Destinations
public import Events
public import Foundation
public import HTTPTypes
public import Instrumentation
import Logging

/// A destination that sends each batch it receives to an HTTP endpoint, as one request, and
/// sends it again until it arrives.
///
/// The wire shape, for a server that ingests these batches:
///
/// - One request per batch, in the order the delivery hands them over, the next batch sent only
///   once the previous one is delivered or dropped.
/// - The method is `POST` and the URL is the configured endpoint.
/// - The header fields are the configured ones, then the trace context of the batch's first
///   record, then `Content-Type`, each replacing fields of the same name before it:
///   - The instrument injects the first (oldest) record's `EventRecord/context`, so a server
///     extracting it joins the request, and the events, to the trace the app was in. Its field
///     names are the instrument's: `traceparent` and `tracestate` for a W3C Trace Context tracer.
///     A record tracked outside any span, or an instrument that injects nothing (the default
///     `NoOpInstrument` when none is bootstrapped), adds no fields.
///   - Only the first record's context travels in the header fields, though a batch may hold
///     records tracked in other traces. A server that needs each record's context reads it from
///     the body, where a ``BatchEncoder`` writes it.
///   - `Content-Type` is always the encoder's ``EncodedBatch/contentType``, whatever a configured
///     field or the instrument wrote.
/// - The body is exactly the encoder's ``EncodedBatch/body`` for the batch's records, oldest
///   first. The format is the encoder's; events need no `Codable` conformance.
/// - A response with a 2xx status means the batch arrived.
/// - A request the transport can never send (``HTTPTransportError/invalidRequest(reason:)``: a
///   malformed or unsupported URL, or an `http` URL App Transport Security refuses) isn't sent
///   again.
/// - No response, a 5xx status, 408 Request Timeout or 429 Too Many Requests means it didn't
///   arrive yet: the same request is sent again after the backoff's next wait, for as long as it
///   takes. A `Retry-After` field is not read; the backoff alone sets the wait.
/// - Any other status means the endpoint won't take the batch, and it isn't sent again.
/// - A record can arrive twice: a request the server took whose response was lost is sent
///   again, and a record a store redelivers after the app was stopped mid-send
///   (`EventRecord/isRedelivered`) may have arrived before. Its `EventRecord/id` is the one it was
///   first sent with, so an encoder that writes each record's identifier lets the server keep one
///   copy.
///
/// ``receive(_:)`` returns once the batch is delivered, dropped, or the delivery is cancelled, so
/// a tracker's store keeps the records of a batch until it arrives, and a batch still being
/// retried when the app ends is delivered again on the next launch. A batch the endpoint rejects,
/// whose request can't be sent, or that the encoder can't encode is dropped: logged at error
/// level and reported on ``dropReports``. Each failed attempt that will be retried is logged at notice level.
/// Cancelling the delivery cancels the send in flight or the wait before the next one, and
/// ``receive(_:)`` returns without logging or reporting it.
///
/// While a batch is retried, the delivery's later batches wait in this destination's buffer,
/// which drops its oldest batch when full (`deliver(to:batchBufferLimit:)`): offline for long
/// enough, the batches dropped there are lost to this run. A store never had them acknowledged,
/// so it delivers them on the next launch; without a store they are gone.
///
/// ```swift
/// let collector = HTTPDestination(
///     endpoint: collectorURL,
///     headerFields: [.authorization: "Bearer \(token)"],
///     encoder: PlansEncoder())
/// let delivery = tracker.records.batch().deliver(to: collector)
/// ```
public struct HTTPDestination<Transport: HTTPTransport, Encoding: BatchEncoder>: Destination {
    private let request: HTTPRequest
    // An existential, not a generic parameter: the default is the bootstrapped
    // `InstrumentationSystem.instrument`, itself `any Instrument`, and a third generic argument
    // would lengthen every spelling of the type for one call per batch beside a network request.
    private let instrument: any Instrument
    private let transport: Transport
    private let encoder: Encoding
    // A closure making each batch's strategy, built where the clock's type is known, rather than
    // a third generic parameter for the clock, for the same reason as `instrument`; and rather
    // than an `any Clock<Duration>`, which Afluent's strategy can't take, and Swift won't open
    // into a `some Clock<Duration>` parameter. A new strategy per batch, as each keeps its count.
    private let retryStrategy: @Sendable () -> any RetryStrategy
    private let reporter = DropReporter<Encoding.Failure>()

    /// A destination that sends batches to `endpoint` through `transport`, encoded by `encoder`,
    /// retrying a send that fails for now with the waits of `backoff` on `clock`.
    ///
    /// - Parameters:
    ///   - endpoint: The URL each batch is posted to.
    ///   - headerFields: The header fields every request carries (an `Authorization`, say); none
    ///     by default. The injected trace context replaces fields of its names, and the encoder's
    ///     content type replaces a `Content-Type`.
    ///   - instrument: What injects each batch's first record's trace context into the header
    ///     fields; the bootstrapped `InstrumentationSystem.instrument`, read once here, by default.
    ///   - transport: What sends each request.
    ///   - encoder: What turns each batch into a request body.
    ///   - backoff: How long to wait before each new attempt at a batch; 1 second, doubling up to
    ///     60 seconds, by default.
    ///   - clock: The clock the waits are measured on.
    public init(
        endpoint: URL,
        headerFields: HTTPFields = [:],
        instrument: any Instrument = InstrumentationSystem.instrument,
        transport: Transport,
        encoder: Encoding,
        backoff: ExponentialBackoff = ExponentialBackoff(),
        clock: some Clock<Duration> = ContinuousClock()
    ) {
        request = HTTPRequest(method: .post, url: endpoint, headerFields: headerFields)
        self.instrument = instrument
        self.transport = transport
        self.encoder = encoder
        retryStrategy = { TransientFailureRetry(backoff, clock: clock) }
    }

    /// A report of each batch dropped without being delivered, in the order they are dropped.
    ///
    /// Reports wait, without a bound, until they are read, so none is missed by reading late.
    /// The sequence has one consumer, and ends once the destination and every copy of it are
    /// gone. Read the sequence into a constant before starting the task that reads it, so the
    /// task holds the sequence and not the destination:
    ///
    /// ```swift
    /// let reports = collector.dropReports
    /// Task {
    ///     for await report in reports {
    ///         logger.warning("Dropped a batch: \(report)")
    ///     }
    /// }
    /// ```
    public var dropReports: AsyncStream<HTTPDropReport<Encoding.Failure>> {
        reporter.reports
    }

    /// Sends `batch` to the endpoint as one request, sends it again after each transient
    /// failure, and returns once it is delivered, dropped or cancelled.
    ///
    /// - Parameter batch: The records to send.
    public func receive(_ batch: [EventRecord]) async {
        switch await send(batch) {
        case .delivered, .cancelled:
            break
        case .rejected(let response):
            logger.error("Dropped a batch the endpoint answered with \(response.status)")
            reporter.report(.rejected(status: response.status, recordIDs: batch.map(\.id)))
        case .invalidRequest(let reason):
            logger.error("Dropped a batch whose request can never be sent: \(reason)")
            reporter.report(.invalidRequest(reason: reason, recordIDs: batch.map(\.id)))
        case .notEncoded(let error):
            logger.error("Dropped a batch the encoder couldn't encode: \(error)")
            reporter.report(.notEncoded(error, recordIDs: batch.map(\.id)))
        case .abandoned(let error):
            logger.error("Stopped sending a batch, whose wait before the next attempt threw: \(error)")
        }
    }

    /// Encodes `batch`, sends it until it is delivered, rejected or cancelled, and says which.
    package func send(_ batch: [EventRecord]) async -> Outcome {
        let encoded: EncodedBatch
        do {
            encoded = try encoder.encode(batch)
        } catch {
            return .notEncoded(error)
        }
        var request = request
        if let first = batch.first {
            instrument.inject(first.context, into: &request.headerFields, using: HTTPFieldsInjector())
        }
        request.headerFields[.contentType] = encoded.contentType
        let attempt = Attempt(transport: transport, request: request, body: encoded.body)
        do {
            // Built for this batch alone: Afluent's strategy keeps its count of retries, and a
            // cancelled unit of work stays cancelled.
            let response = try await DeferredTask { try await attempt.run() }
                .retry(retryStrategy())
                .execute()
            return .delivered(response)
        } catch AttemptFailure.rejected(let response) {
            return .rejected(response)
        } catch AttemptFailure.invalidRequest(let reason) {
            return .invalidRequest(reason)
        } catch is CancellationError {
            return .cancelled
        } catch {
            // Reached only through a clock whose sleep throws something other than
            // CancellationError: with Afluent 1.1.46 the retry throws the attempt's errors
            // (AttemptFailure or CancellationError) and its strategy's, which are the sleep's.
            // Retrying would spin on a clock that keeps throwing, and receive must return, so the
            // batch is given up on for this run, logged rather than reported as a drop.
            return .abandoned(error)
        }
    }

    /// What became of one batch.
    package enum Outcome {
        /// The server answered with a 2xx status.
        case delivered(HTTPResponse)
        /// The server answered with a status that retrying won't change.
        case rejected(HTTPResponse)
        /// The transport can never send the request.
        case invalidRequest(String)
        /// The encoder threw, so nothing was sent.
        case notEncoded(Encoding.Failure)
        /// The delivery was cancelled before the batch was delivered or dropped.
        case cancelled
        /// The clock's sleep before the next attempt threw `error`, not `CancellationError`.
        case abandoned(any Error)
    }
}

/// One send of a batch's request, which throws what kept it from being delivered.
private struct Attempt<Transport: HTTPTransport>: Sendable {
    let transport: Transport
    let request: HTTPRequest
    let body: Data

    /// Sends the request; throws `CancellationError` when cancelled, so the retry stops, and an
    /// ``AttemptFailure`` when the batch wasn't delivered.
    func run() async throws -> HTTPResponse {
        let response: HTTPResponse
        do {
            response = try await transport.send(request, body: body)
        } catch .cancelled where Task.isCancelled {
            throw CancellationError()
        } catch .cancelled {
            // A transport that says it was cancelled while the delivery wasn't got no response;
            // ending the retries here would let a store forget a batch that never arrived.
            logger.notice("A batch's send was cancelled by its transport, not the delivery, so it will be sent again")
            throw AttemptFailure.unanswered(reason: "cancelled by the transport")
        } catch .failed(let reason) {
            logger.notice("A batch got no response, so it will be sent again: \(reason)")
            throw AttemptFailure.unanswered(reason: reason)
        } catch .invalidRequest(let reason) {
            throw AttemptFailure.invalidRequest(reason: reason)
        }
        switch response.status {
        case let status where status.kind == .successful:
            return response
        case let status where status.isTransient:
            logger.notice("The endpoint answered a batch with \(status), so it will be sent again")
            throw AttemptFailure.unavailable(response)
        default:
            throw AttemptFailure.rejected(response)
        }
    }
}

/// The drop reports a destination and its copies share, ended once the last copy is gone.
private final class DropReporter<Failure: Error>: Sendable {
    let reports: AsyncStream<HTTPDropReport<Failure>>
    private let continuation: AsyncStream<HTTPDropReport<Failure>>.Continuation

    init() {
        (reports, continuation) = AsyncStream.makeStream(of: HTTPDropReport<Failure>.self)
    }

    deinit {
        continuation.finish()
    }

    func report(_ report: HTTPDropReport<Failure>) {
        continuation.yield(report)
    }
}

// At file scope because a generic type can't hold a static stored property; one logger for every
// specialization of HTTPDestination.
private let logger = Logger(label: "HTTPDestinations.HTTPDestination")
