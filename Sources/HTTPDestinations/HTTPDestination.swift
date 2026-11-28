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
/// - A response with a 2xx status means the request arrived, and the encoder reads its body to
///   say whether the vendor stored it (``BatchEncoder/outcome(of:for:)``): most vendors answer 2xx
///   only to what they store, and their encoders count every 2xx as delivered. A vendor that
///   answers 2xx to a request it stores nothing of, and says so in the body (Mixpanel's
///   `{"status": 0, "error": ...}`), has the request dropped and reported
///   (``HTTPDropReport/rejectedInBody(status:reason:recordIDs:)``), or, for a refusal its vendor
///   says may pass, sent again as after a 5xx, until the request's deadline. An encoder should
///   count a body it can't read, an empty one included, as delivered, so an answer that changes
///   shape never makes the destination send the same request again and again; the
///   DestinationTesting conformance kit checks that it does.
/// - A request the transport can never send (``HTTPTransportError/invalidRequest(reason:)``: a
///   malformed or unsupported URL, or an `http` URL App Transport Security refuses) isn't sent
///   again.
/// - No response, a 5xx status, 408 Request Timeout, 429 Too Many Requests, or a status the
///   encoder lists in ``BatchEncoder/transientStatuses`` means it didn't arrive yet: the same
///   request is sent again after the backoff's next wait, for as long as it takes. A
///   `Retry-After` field is not read; the backoff alone sets the wait.
/// - Any other status means the endpoint won't take the request, and it isn't sent again. The
///   batch's later requests are still sent.
/// - A request with a deadline (``EncodedRequest/deadline``) is sent only while the destination's
///   wall clock reads that time or earlier, checked before every attempt, the first included, and
///   again when an attempt fails. One still undelivered once it has passed isn't sent again, and
///   is reported without waiting out a backoff, so a vendor that would misdate or ignore records
///   that old never receives them. The whole request is dropped, its younger records too; the
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
/// rejects, by its status or in a 2xx answer's body, that can't be sent or that passed its
/// deadline, a batch the encoder can't encode, and
/// a record the encoder leaves out of its requests are dropped: logged at error level and
/// reported on ``dropReports``. Each failed attempt that will be retried is logged at notice
/// level.
/// Cancelling the delivery cancels the send in flight or the wait before the next one, and
/// ``receive(_:)`` returns without logging or reporting it, or sending the batch's later
/// requests. A request whose wait before the next attempt throws something other than
/// `CancellationError` (a custom clock's failure) is given up on, logged at error level but not
/// reported, and the batch's next request is sent.
///
/// While a batch is retried, the delivery's later batches wait in this destination's buffer,
/// which drops its oldest batch when full and reports it on the delivery's `bufferDropReports`.
/// With a store, a dropped batch's records aren't lost: once this destination has caught up, the
/// delivery reads them back from the store and hands them to it again, in the same run, so they
/// are sent once the endpoint answers.
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
    // A wall clock beside `clock`, as a deadline is a moment in the world (a record's timestamp
    // plus a vendor's window) while the waits are durations; a `Clock<Duration>`'s instants can't
    // be compared with a Date. The closure form is what `Tracker(now:)` and the vendor encoders
    // take, so a factory hands one function to both its encoder and its destination.
    private let now: @Sendable () -> Date
    // The encoder's statuses, read once: a static requirement, so the same for every request.
    // Statuses rather than TransientStatus values, as an answer is compared by its status.
    private let transientStatuses: Set<HTTPResponse.Status>
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
    ///     60 seconds, with full jitter, by default.
    ///   - clock: The clock the waits are measured on.
    ///   - randomNumberGenerator: The source of the backoff's jitter, which this destination, its
    ///     copies and every request they retry draw from in turn, one draw a wait; the system's
    ///     generator by default. Pass a seeded generator in tests only: it makes the waits
    ///     reproducible while one request retries at a time (copies retrying at once share its
    ///     draws in the order they ask), and in production it would make every device wait the
    ///     same, which defeats the jitter.
    ///   - now: The wall-clock time, read before each attempt at a request with a deadline
    ///     (``EncodedRequest/deadline``); the system's clock by default.
    public init(
        endpoint: URL,
        headerFields: HTTPFields = [:],
        instrument: any Instrument = InstrumentationSystem.instrument,
        transport: Transport,
        encoder: Encoding,
        backoff: ExponentialBackoff = ExponentialBackoff(),
        clock: some Clock<Duration> = ContinuousClock(),
        randomNumberGenerator: some RandomNumberGenerator & Sendable = SystemRandomNumberGenerator(),
        now: @escaping @Sendable () -> Date = { Date.now }
    ) {
        request = HTTPRequest(method: .post, url: endpoint, headerFields: headerFields)
        self.instrument = instrument
        self.transport = transport
        self.encoder = encoder
        // One generator for every request, rather than a copy per request, which would give a
        // seeded generator's same waits to each request, and to each destination copy.
        let generator = SharedRandomNumberGenerator(randomNumberGenerator)
        retryStrategy = { TransientFailureRetry(backoff, clock: clock, generator: generator) }
        self.now = now
        transientStatuses = Set(Encoding.transientStatuses.map(\.status))
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
            case .rejectedInBody(let response, let reason):
                logger.error("Dropped a request the endpoint answered with \(response.status), whose body says it stored nothing: \(reason)")
                reporter.report(.rejectedInBody(status: response.status, reason: reason, recordIDs: request.recordIDs))
            case .invalidRequest(let reason):
                logger.error("Dropped a request that can never be sent: \(reason)")
                reporter.report(.invalidRequest(reason: reason, recordIDs: request.recordIDs))
            case .deadlineExceeded(let deadline):
                logger.error("Dropped a request still undelivered at its deadline, \(deadline)")
                reporter.report(.deadlineExceeded(deadline: deadline, recordIDs: request.recordIDs))
            case .abandoned(let error):
                logger.error("Stopped sending a request, whose wait before the next attempt threw: \(error)")
            }
        }
    }

    /// Sends `encoded` until it is delivered, rejected, past its deadline or cancelled, with the
    /// trace context of `context` in its header fields, and says which.
    package func send(_ encoded: EncodedRequest, context: ServiceContext?) async -> Outcome {
        var request = request
        if let context {
            instrument.inject(context, into: &request.headerFields, using: HTTPFieldsInjector())
        }
        request.headerFields[.contentType] = encoded.body.contentType
        let attempt = Attempt<Transport, Encoding>(transport: transport, request: request, encoded: encoded, transientStatuses: transientStatuses, now: now)
        do {
            // Built for this request alone: Afluent's strategy keeps its count of retries, and a
            // cancelled unit of work stays cancelled.
            let response = try await DeferredTask { try await attempt.run() }
                .retry(retryStrategy())
                .execute()
            return .delivered(response)
        } catch AttemptFailure.rejected(let response) {
            return .rejected(response)
        } catch AttemptFailure.rejectedInBody(let response, let reason) {
            return .rejectedInBody(response, reason: reason)
        } catch AttemptFailure.invalidRequest(let reason) {
            return .invalidRequest(reason)
        } catch AttemptFailure.deadlineExceeded(let deadline) {
            return .deadlineExceeded(deadline)
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
        /// The server answered with a 2xx status, whose body the encoder reads as delivered.
        case delivered(HTTPResponse)
        /// The server answered with a status that retrying won't change.
        case rejected(HTTPResponse)
        /// The server answered with a 2xx status, whose body the encoder reads as storing nothing,
        /// for `reason`, which retrying won't change.
        case rejectedInBody(HTTPResponse, reason: String)
        /// The transport can never send the request.
        case invalidRequest(String)
        /// The request's deadline, `deadline`, passed before it was delivered.
        case deadlineExceeded(Date)
        /// The delivery was cancelled before the request was delivered or dropped.
        case cancelled
        /// The clock's sleep before the next attempt threw `error`, not `CancellationError`.
        case abandoned(any Error)
    }
}

/// One send of a batch's request, which throws what kept it from being delivered.
///
/// Generic over the encoder, whose ``BatchEncoder/outcome(of:for:)`` reads a 2xx answer's body.
private struct Attempt<Transport: HTTPTransport, Encoding: BatchEncoder>: Sendable {
    let transport: Transport
    let request: HTTPRequest
    let encoded: EncodedRequest
    /// The statuses retried beside ``HTTPResponse/Status/isTransient``'s, from the encoder.
    let transientStatuses: Set<HTTPResponse.Status>
    let now: @Sendable () -> Date

    private var body: Data { encoded.body.body }
    private var deadline: Date? { encoded.deadline }

    /// Sends the request; throws `CancellationError` when cancelled, so the retry stops, and an
    /// ``AttemptFailure`` when the batch wasn't delivered.
    func run() async throws -> HTTPResponse {
        // Inside the retried unit of work, so every attempt, the first included, checks it, and
        // the retry strategy ends the retries on what it throws. Rejected: a strategy that reads
        // the clock before each retry, which would leave the first attempt unchecked and put the
        // drop's report in two places.
        if let deadline {
            // A cancelled delivery is cancelled, not a drop: the batch comes back whole after a
            // relaunch, and a report here would be the first of two for one request.
            try Task.checkCancellation()
            // Written as the window's inside, so a NaN reading, on either side, is past it and
            // the request is reported (D10), rather than sent to a vendor that would misdate it.
            guard now() <= deadline else {
                throw AttemptFailure.deadlineExceeded(deadline)
            }
        }
        let response: HTTPTransportResponse
        do {
            response = try await transport.send(request, body: body)
        } catch .cancelled where Task.isCancelled {
            throw CancellationError()
        } catch .cancelled {
            // A transport that says it was cancelled while the delivery wasn't got no response;
            // ending the retries here would let a store forget a batch that never arrived.
            throw retried(.unanswered(reason: "cancelled by the transport"), "A batch's send was cancelled by its transport, not the delivery, so it will be sent again")
        } catch .failed(let reason) {
            throw retried(.unanswered(reason: reason), "A batch got no response, so it will be sent again: \(reason)")
        } catch .invalidRequest(let reason) {
            throw AttemptFailure.invalidRequest(reason: reason)
        }
        switch response.head.status {
        case let status where status.kind == .successful:
            return try delivered(response)
        case let status where status.isTransient || transientStatuses.contains(status):
            throw retried(.unavailable(response.head), "The endpoint answered a batch with \(status), so it will be sent again")
        default:
            throw AttemptFailure.rejected(response.head)
        }
    }

    /// `response`, a 2xx answer, when its encoder reads the body as delivered; throws the
    /// ``AttemptFailure`` of one it reads as storing nothing.
    private func delivered(_ response: HTTPTransportResponse) throws(AttemptFailure) -> HTTPResponse {
        switch Encoding.outcome(of: response, for: encoded) {
        case .delivered:
            return response.head
        case .rejected(let reason):
            throw .rejectedInBody(response.head, reason: reason)
        case .transient(let reason):
            // The same path as a 5xx: the backoff, and the deadline checked first.
            throw retried(.unavailable(response.head), "The endpoint answered a batch with \(response.head.status), but its body says it stored nothing for now, so it will be sent again: \(reason)")
        }
    }

    /// `failure`, which the retry strategy sends again after a backoff, or
    /// ``AttemptFailure/deadlineExceeded(_:)`` when the deadline has passed by now.
    ///
    /// Checked when the send fails as well as before it, so a request whose deadline passed while
    /// it was in flight is reported at once rather than after a backoff that ends in the drop.
    private func retried(_ failure: AttemptFailure, _ notice: @autoclosure () -> Logger.Message) -> AttemptFailure {
        if let deadline, !(now() <= deadline) {
            return .deadlineExceeded(deadline)
        }
        logger.notice(notice())
        return failure
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
