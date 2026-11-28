/// What a successful (2xx) answer to a request means, as its ``BatchEncoder`` reads the answer's
/// body (``BatchEncoder/outcome(of:for:)``).
///
/// Most vendors store what they answer 2xx to, and their encoders return ``delivered``. Some answer
/// 2xx to a request they store nothing of, and say so in the body only, as Mixpanel's track API
/// does with `{"status": 0, "error": ...}`: their encoders read it and return ``rejected(reason:)``
/// or ``transient(reason:)``.
public enum ResponseOutcome: Sendable, Hashable {
    /// The vendor stored the request's records: ``HTTPDestination`` counts them as delivered.
    case delivered
    /// The vendor stored none of the request's records, and wouldn't if it were sent again, for
    /// `reason`, the vendor's own words where its body has them: ``HTTPDestination`` drops the
    /// request and reports it as ``HTTPDropReport/rejectedInBody(status:reason:recordIDs:)``.
    case rejected(reason: String)
    /// The vendor stored none of the request's records for now, for `reason`, and may store them
    /// if it is sent again: ``HTTPDestination`` sends it again as it does after a 5xx, with the
    /// same backoff and the same deadline.
    ///
    /// Only the request's ``EncodedRequest/deadline`` ends the retries: a request without one is
    /// sent again for as long as the vendor answers this way. An encoder whose requests have no
    /// deadline returns ``rejected(reason:)`` instead, unless the vendor documents that the answer
    /// passes.
    case transient(reason: String)
}
