public import Events
public import Trackers

extension Sampler {
    /// A sampler that keeps or drops whole sessions, keeping each with probability `rate`: every
    /// record of a session gets the same decision.
    ///
    /// It samples by each record's ``SessionKey``, so it needs the sessions enricher among the
    /// tracker's enrichers, which run before its samplers:
    ///
    /// ```swift
    /// let tracker = Tracker(enrichers: [.sessions()], samplers: [.sessions(rate: try SampleRate(0.1))])
    /// ```
    ///
    /// A session's decision is made from the tracker's sampling seed and the session's identifier,
    /// and from nothing else, so its ``SessionStarted`` and ``SessionEnded`` go with it. Nothing
    /// is kept to remember the decision but the current session's, in memory, and the identifier
    /// is never written anywhere. A record with no session, such as one tracked without the
    /// sessions enricher, isn't sampled by it.
    ///
    /// - Parameters:
    ///   - selects: Whether the sampler applies to a record; every record by default. Records it
    ///     doesn't apply to are kept whatever their session's decision.
    ///   - rate: The fraction of the sessions to keep.
    /// - Returns: The sampler.
    public static func sessions(where selects: @escaping @Sendable (EventRecord) -> Bool = { _ in true }, rate: SampleRate) -> Sampler {
        .grouped(by: SessionKey.self, where: selects, rate: rate)
    }
}
