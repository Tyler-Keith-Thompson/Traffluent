public import Foundation
public import HTTPDestinations
public import TrackingPlans

/// What a ``DestinationConformance`` check hands the vendor's factory: the plan of the events it
/// sends, the transport to send them through, a backoff short enough that a retry doesn't hold the
/// test up, and when its records were tracked.
public struct DestinationSetup: Sendable {
    /// The tracking plan of every event the check sends; the encoder must be made with it.
    public var plan: TrackingPlan
    /// The transport the destination must send through.
    public var transport: ScriptedTransport
    /// The backoff the destination must retry with.
    public var backoff: ExponentialBackoff
    /// When every record the check sends was tracked. A destination whose encoder leaves out
    /// records by their age is given this as the time it encodes at, so the check's records are
    /// sent whenever the test runs.
    public var timestamp: Date

    /// A setup of `plan`, `transport`, `backoff` and `timestamp`.
    ///
    /// - Parameters:
    ///   - plan: The tracking plan of every event the check sends.
    ///   - transport: The transport the destination must send through.
    ///   - backoff: The backoff the destination must retry with.
    ///   - timestamp: When every record the check sends was tracked; the time the checks stamp
    ///     their records with by default.
    public init(plan: TrackingPlan, transport: ScriptedTransport, backoff: ExponentialBackoff, timestamp: Date = .conformanceTimestamp) {
        self.plan = plan
        self.transport = transport
        self.backoff = backoff
        self.timestamp = timestamp
    }
}
