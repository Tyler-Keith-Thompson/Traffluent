public import HTTPDestinations
public import TrackingPlans

/// What a ``DestinationConformance`` check hands the vendor's factory: the plan of the events it
/// sends, the transport to send them through, and a backoff short enough that a retry doesn't
/// hold the test up.
public struct DestinationSetup: Sendable {
    /// The tracking plan of every event the check sends; the encoder must be made with it.
    public var plan: TrackingPlan
    /// The transport the destination must send through.
    public var transport: ScriptedTransport
    /// The backoff the destination must retry with.
    public var backoff: ExponentialBackoff

    /// A setup of `plan`, `transport` and `backoff`.
    ///
    /// - Parameters:
    ///   - plan: The tracking plan of every event the check sends.
    ///   - transport: The transport the destination must send through.
    ///   - backoff: The backoff the destination must retry with.
    public init(plan: TrackingPlan, transport: ScriptedTransport, backoff: ExponentialBackoff) {
        self.plan = plan
        self.transport = transport
        self.backoff = backoff
    }
}
