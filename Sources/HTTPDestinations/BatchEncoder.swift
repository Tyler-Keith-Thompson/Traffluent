public import Events

/// What turns a batch of records into the requests ``HTTPDestination`` sends.
///
/// Events need no `Codable` conformance: an encoder reads the events it knows by casting each
/// record's `EventRecord.event` to their types, and chooses the wire format and its content type.
/// An encoder for a server that deduplicates writes each record's `EventRecord.id`, which a
/// redelivered record keeps.
///
/// An encoder for an endpoint without limits returns one request carrying every record:
///
/// ```swift
/// struct PlansEncoder: BatchEncoder {
///     static let transientStatuses: Set<TransientStatus> = []
///
///     static func outcome(of response: HTTPTransportResponse, for request: EncodedRequest) -> ResponseOutcome {
///         .delivered
///     }
///
///     func requests(for batch: [EventRecord]) -> BatchRequests<Never> {
///         let plans = batch.compactMap { ($0.event as? SignedUp)?.plan }
///         let body = EncodedBatch(body: Data(plans.joined(separator: "\n").utf8), contentType: "text/plain")
///         return BatchRequests(requests: [EncodedRequest(body: body, recordIDs: batch.map(\.id))], skippedRecords: [])
///     }
/// }
/// ```
///
/// An encoder for an endpoint that limits each request, by its size or its count of events,
/// splits the batch into requests the endpoint takes, and leaves out a record that fits in none
/// of them, or that it can't encode, as a ``SkippedRecord``. One whose ``requests(for:)`` doesn't
/// throw names its reasons' type as ``Failure`` (`typealias Failure = VendorEncodingError`), which
/// a method that doesn't throw leaves Swift unable to infer.
///
/// Every encoder states ``transientStatuses``: an empty set for an endpoint that answers only
/// 408, 429 or a 5xx to a request worth sending again, or each other failure status its vendor
/// answers to one, which ``HTTPDestination`` then retries as it retries those. It states too what a
/// 2xx answer means (``outcome(of:for:)``): ``ResponseOutcome/delivered`` for a vendor that stores what
/// it answers 2xx to, or what the answer's body says for one that answers 2xx to a request it
/// stores nothing of.
public protocol BatchEncoder: Sendable {
    /// What ``requests(for:)`` throws, and why a record was left out; `Never` for an encoder that
    /// can't fail.
    associatedtype Failure: Error

    /// The requests that carry `batch`, which ``HTTPDestination`` sends one after another, and the
    /// records left out of them.
    ///
    /// Each request's `recordIDs` are the records its body holds: ``HTTPDestination`` reports
    /// those when it drops the request.
    ///
    /// - Parameter batch: Records of tracked events, oldest first; never empty.
    /// - Returns: The requests, in the order they are sent, and each record left out, with why.
    /// - Throws: `Failure` when nothing of the batch can be encoded; ``HTTPDestination`` then
    ///   sends nothing for it and reports every record as one drop.
    func requests(for batch: [EventRecord]) throws(Failure) -> BatchRequests<Failure>

    /// The failure statuses, beyond 408 Request Timeout, 429 Too Many Requests and every 5xx, that
    /// ``HTTPDestination`` sends a request of this encoder again after: `[]` for none.
    ///
    /// A vendor fact, the same for every request and every instance, so ``HTTPDestination`` reads
    /// it once, when it is made. Any other status but a 2xx still drops the request, reported as
    /// ``HTTPDropReport/rejected(status:recordIDs:)``. An encoder that wraps another forwards the
    /// wrapped encoder's set (`static var transientStatuses: Set<TransientStatus> {
    /// Wrapped.transientStatuses }`), or its requests lose the vendor's retries.
    ///
    /// There is no default, so a conformer that leaves it out, or declares it with another type
    /// (an array, say), doesn't compile, rather than silently retrying nothing more.
    static var transientStatuses: Set<TransientStatus> { get }

    /// What the successful (2xx) answer `response` to `request`, one of this encoder's requests,
    /// means: whether the vendor stored the request's records.
    ///
    /// ``HTTPDestination`` calls it for every 2xx answer, and only for those, with the answer's
    /// status, header fields and body, and the request it answers, for a vendor whose answer is
    /// read against what was sent (a count of the records it took, say). An encoder for a vendor that stores what it answers 2xx to
    /// returns ``ResponseOutcome/delivered``. One for a vendor that answers 2xx to a request it
    /// stores nothing of, and says so in the body (Mixpanel's `{"status": 0, "error": ...}`),
    /// returns ``ResponseOutcome/rejected(reason:)``, which drops and reports the request, or
    /// ``ResponseOutcome/transient(reason:)``, which sends it again. A body the vendor doesn't
    /// document, an empty one or one that doesn't parse included, is
    /// ``ResponseOutcome/delivered``: the request did arrive, and sending it again after an
    /// answer the encoder can't read would repeat it for as long as the vendor keeps answering
    /// that way. The conformance kit's `unreadableSuccessDelivered` check holds an encoder to
    /// this. An encoder that wraps another forwards the wrapped encoder's outcome.
    ///
    /// A transient outcome is sent again until it is delivered, rejected, or past the request's
    /// ``EncodedRequest/deadline``. A request with no deadline is sent again for as long as the
    /// vendor keeps answering that way, so an encoder whose requests have none returns
    /// ``ResponseOutcome/rejected(reason:)`` rather than ``ResponseOutcome/transient(reason:)``
    /// unless the vendor documents that the answer passes.
    ///
    /// A vendor fact, as ``transientStatuses`` is, so it is static, with no default: a conformer
    /// that leaves it out, or misspells it, doesn't compile, rather than silently counting a
    /// refused request as delivered.
    ///
    /// - Parameters:
    ///   - response: The answer: a 2xx status, its header fields and its body.
    ///   - request: The request it answers, as the encoder made it.
    /// - Returns: Whether the request's records were delivered, refused for good, or refused for
    ///   now.
    static func outcome(of response: HTTPTransportResponse, for request: EncodedRequest) -> ResponseOutcome
}
