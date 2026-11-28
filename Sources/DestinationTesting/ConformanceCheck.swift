/// One rule every vendor destination keeps, which ``DestinationConformance/expect(_:sourceLocation:)``
/// checks.
///
/// Pass every case to a parameterized test, so each rule is a test case of its own:
///
/// ```swift
/// @Test(arguments: ConformanceCheck.allCases)
/// func conformance(check: ConformanceCheck) async throws {
///     try await conformance.expect(check)
/// }
/// ```
public enum ConformanceCheck: String, Sendable, Hashable, CaseIterable, CustomStringConvertible {
    /// A `Sensitive` value is never sent by the default destination, even by a record that reveals
    /// it. With the adopter's opt-in, it is sent while the record reveals it, and not once the
    /// record is redacted.
    case sensitiveValuesRedacted
    /// Behind a tracker's `Consent` and the destination's `accepting(_:)`, the destination sends
    /// the event of a granted category it accepts, and not the event of a denied category or of
    /// one it doesn't accept.
    ///
    /// The tracker and `accepting(_:)` do the gating, so this checks that the destination sends
    /// exactly the records it is handed: one that sends records it kept from elsewhere, or drops
    /// what it is handed, breaks it. It doesn't check a consent rule of the destination's own.
    case consentHolds
    /// A record too large for the vendor's limit is left out and reported as
    /// `HTTPDropReport.skipped(_:)`, and the batch's other records are sent.
    ///
    /// A limit with no byte cap on a record or a request under 64 MiB, such as
    /// `BatchLimit.unlimited`, leaves no record the check could make too large, so the check sends
    /// nothing and records no issue.
    case oversizedRecordSkipped
    /// A request that gets no response, a 5xx, 408, 429 or a status of the encoder's
    /// `BatchEncoder.transientStatuses` is sent again, byte for byte, until it is delivered, and
    /// nothing is reported.
    case transientFailuresRetried
    /// A request answered with a status retrying won't change (400, 401, 403, 404, 413, 422, less
    /// any the encoder lists in `BatchEncoder.transientStatuses`) is sent once and reported as
    /// `HTTPDropReport.rejected(status:recordIDs:)`. An encoder that lists all six is checked
    /// with the first client error (4xx) it doesn't list; one that lists every client error
    /// records an issue, as no rejection is left to check.
    case rejectionsDropped
    /// A request answered 2xx with a body no vendor writes, an empty one or one that isn't JSON,
    /// is sent once and nothing is reported: the encoder's `BatchEncoder.outcome(of:for:)` counts an
    /// answer it can't read as delivered, so a vendor's answer that changes shape never makes the
    /// destination send the same request again and again, or drop what the vendor stored.
    case unreadableSuccessDelivered
    /// No request carries a trace context in its header fields (`traceparent`, `tracestate`, or
    /// whatever the instrument injects), even while a tracer is active and the record was tracked
    /// in a span: a vendor's destination passes `NoOpInstrument()`, so the app's traces stay in
    /// the app.
    case traceContextWithheld

    /// The check's name.
    public var description: String {
        rawValue
    }
}
