import Afluent
public import AsyncQueues
public import Destinations
public import Events
public import Foundation
public import HTTPTypes
public import Instrumentation
import Logging

/// A destination that sends each batch it receives to an HTTP endpoint, as the requests its encoder
/// splits it into, and sends each again until it arrives.
///
/// The wire shape, for a server that ingests these batches:
///
/// - The requests the encoder splits each batch into (``BatchEncoder/requests(for:)``), in the
///   order the delivery hands batches over, each request sent only once the previous one is
///   delivered or dropped.
/// - The method is `POST` and the URL is the configured endpoint.
/// - The header fields are the configured ones, then the trace context of the request's first
///   record, then `Content-Type`, each replacing fields of the same name before it:
///   - The instrument injects the first (oldest) record's `EventRecord/context`, so a server
///     extracting it joins the request, and the events, to the trace the app was in. Its field
///     names are the instrument's: `traceparent` and `tracestate` for a W3C Trace Context tracer.
///     A record tracked outside any span, or an instrument that injects nothing (the default
///     `NoOpInstrument` when none is bootstrapped), adds no fields.
///   - Only the first record's context travels in the header fields, though a request may hold
///     records tracked in other traces. A server that needs each record's context reads it from
///     the body, where a ``BatchEncoder`` writes it.
///   - `Content-Type` is always the encoder's ``EncodedBatch/contentType``, whatever a configured
///     field or the instrument wrote.
/// - The body is exactly the encoder's ``EncodedBatch/body`` for the request's records, oldest
///   first. The format is the encoder's; events need no `Codable` conformance.
/// - A response with a 2xx status means the batch arrived.
/// - A request the transport can never send (``HTTPTransportError/invalidRequest(reason:)``: a
///   malformed or unsupported URL, or an `http` URL App Transport Security refuses) isn't sent
///   again.
/// - No response, a 5xx status, 408 Request Timeout or 429 Too Many Requests means it didn't
///   arrive yet: the same request is sent again after the backoff's next wait, for as long as it
///   takes. A `Retry-After` field is not read; the backoff alone sets the wait.
/// - Any other status means the endpoint won't take the request, and it isn't sent again. The
///   batch's later requests are still sent.
/// - A record can arrive twice: a request the server took whose response was lost is sent
///   again, and a record a store redelivers after the app was stopped mid-send
///   (`EventRecord/isRedelivered`) may have arrived before. Its `EventRecord/id` is the one it was
///   first sent with, so an encoder that writes each record's identifier lets the server keep one
///   copy.
/// - A batch of several requests is acknowledged only once every request is delivered or dropped.
///   A delivery cancelled, or an app stopped, after some of its requests arrived hands the whole
///   batch over again, so those requests are sent again too: a server that keeps one copy per
///   record identifier absorbs them. The records the encoder leaves out are then reported again.
///
/// ``receive(_:)`` returns once the batch is delivered, dropped, or the delivery is cancelled, so
/// a tracker's store keeps the records of a batch until it arrives, and a batch still being
/// retried when the app ends is delivered again on the next launch. A request the endpoint
/// rejects or that can't be sent, a batch the encoder can't encode, and a record the encoder
/// leaves out of its requests are dropped: logged at error level and reported on
/// ``dropReports``. Each failed attempt that will be retried is logged at notice level.
/// Cancelling the delivery cancels the send in flight or the wait before the next one, and
/// ``receive(_:)`` returns without logging or reporting it, or sending the batch's later
/// requests. A request whose wait before the next attempt throws something other than
/// `CancellationError` (a custom clock's failure) is given up on, logged at error level but not
/// reported, and the batch's next request is sent.
///
/// While a batch is retried, the delivery's later batches wait in this destination's buffer,
/// which drops its oldest batch when full and reports it
/// (`deliver(to:batchBufferLimit:bufferDropReporter:)`). With a store, a dropped batch's records
/// aren't lost: once this destination has caught up, the delivery reads them back from the store
/// and hands them to it again, in the same run, so they are sent once the endpoint answers.
/// Without a store, the records of a dropped batch are lost.
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
    // A closure making each request's strategy, built where the clock's type is known, rather than
    // a third generic parameter for the clock, for the same reason as `instrument`; and rather
    // than an `any Clock<Duration>`, which Afluent's strategy can't take, and Swift won't open
    // into a `some Clock<Duration>` parameter. A new strategy per request, as each keeps its count.
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
    ///   - encoder: What turns each batch into requests.
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
    /// The sequence ends once the destination and every copy of it are gone and every report has
    /// been read. Read the sequence into a constant before starting the task that reads it, so
    /// the task holds the sequence and not the destination:
    ///
    /// ```swift
    /// let reports = collector.dropReports
    /// Task {
    ///     for await report in reports {
    ///         logger.warning("Dropped a batch: \(report)")
    ///     }
    /// }
    /// ```
    ///
    /// One task reads the reports at a time. The first iterator to read holds them until its
    /// iteration ends or it is released; a second reader meanwhile waits its turn, logging a
    /// warning once, then reads on from the next report, so the first gets every report in order.
    /// A reader cancelled while it waits returns `nil`.
    public var dropReports: AsyncQueue<HTTPDropReport<Encoding.Failure>> {
        reporter.reports
    }

    /// Sends `batch` to the endpoint, as the requests its encoder splits it into, one after
    /// another; sends each again after each transient failure, and returns once every one is
    /// delivered or dropped, or the delivery is cancelled.
    ///
    /// - Parameter batch: The records to send.
    public func receive(_ batch: [EventRecord]) async {
        let encoded: BatchRequests<Encoding.Failure>
        do {
            encoded = try encoder.requests(for: batch)
        } catch {
            logger.error("Dropped a batch the encoder couldn't encode: \(error)")
            reporter.report(.notEncoded(error, recordIDs: batch.map(\.id)))
            return
        }
        for skipped in encoded.skippedRecords {
            logger.error("Left a record of \(skipped.eventName) version \(skipped.schemaVersion) out of the batch: \(skipped.reason)")
            reporter.report(.skipped(skipped))
        }
        // Each request's trace context is its own first record's. A dictionary, as a request
        // names its records by identifier; of two records of one identifier, the first's.
        let contexts = Dictionary(batch.map { ($0.id, $0.context) }) { first, _ in first }
        for request in encoded.requests {
            let context = request.recordIDs.first.flatMap { contexts[$0] }
            switch await send(request, context: context) {
            case .delivered:
                break
            case .cancelled:
                return
            case .rejected(let response):
                logger.error("Dropped a request the endpoint answered with \(response.status)")
                reporter.report(.rejected(status: response.status, recordIDs: request.recordIDs))
            case .invalidRequest(let reason):
                logger.error("Dropped a request that can never be sent: \(reason)")
                reporter.report(.invalidRequest(reason: reason, recordIDs: request.recordIDs))
            case .abandoned(let error):
                logger.error("Stopped sending a request, whose wait before the next attempt threw: \(error)")
            }
        }
    }

    /// Sends `encoded` until it is delivered, rejected or cancelled, with the trace context of
    /// `context` in its header fields, and says which.
    package func send(_ encoded: EncodedRequest, context: ServiceContext?) async -> Outcome {
        var request = request
        if let context {
            instrument.inject(context, into: &request.headerFields, using: HTTPFieldsInjector())
        }
        request.headerFields[.contentType] = encoded.body.contentType
        let attempt = Attempt(transport: transport, request: request, body: encoded.body.body)
        do {
            // Built for this request alone: Afluent's strategy keeps its count of retries, and a
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
            // CancellationError: Afluent's retry throws the attempt's errors (AttemptFailure or
            // CancellationError) and its strategy's, which are the sleep's. Retrying would spin
            // on a clock that keeps throwing, and receive must return, so the request is given
            // up on for this run, logged rather than reported as a drop.
            return .abandoned(error)
        }
    }

    /// What became of one request.
    package enum Outcome {
        /// The server answered with a 2xx status.
        case delivered(HTTPResponse)
        /// The server answered with a status that retrying won't change.
        case rejected(HTTPResponse)
        /// The transport can never send the request.
        case invalidRequest(String)
        /// The delivery was cancelled before the request was delivered or dropped.
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
    let reports = AsyncQueue<HTTPDropReport<Failure>>(name: "an HTTPDestination's drop reports")

    deinit {
        reports.finish()
    }

    func report(_ report: HTTPDropReport<Failure>) {
        reports.enqueue(report)
    }
}

// At file scope because a generic type can't hold a static stored property; one logger for every
// specialization of HTTPDestination.
private let logger = Logger(label: "HTTPDestinations.HTTPDestination")
