public import Events

extension Enricher {
    /// An enricher that sets every record's ``NetworkKey`` to the connection the device uses when
    /// the tracker's worker reaches it, or, given to a destination with `enriched(by:)`, when the
    /// delivery hands that destination the record's batch.
    ///
    /// ```swift
    /// let tracker = Tracker(enrichers: [.network()])
    /// ```
    ///
    /// On Apple platforms the enricher starts an `NWPathMonitor` of its own, which runs while
    /// any tracker, copy or destination holds the enricher and stops when the last lets it go: give
    /// each tracker its own call. Records the worker reaches before the monitor's first report carry no key.
    /// Off Apple platforms there is no monitor, and the enricher sets nothing.
    ///
    /// The connection is read for each event, unlike the other standard values, as it changes
    /// while the app runs: a copy of the monitor's latest report, kept under a lock.
    ///
    /// - Returns: The enricher, which runs on the tracker's worker like any other, or in a
    ///   destination's delivery when given to one.
    public static func network() -> Enricher {
        #if canImport(Network)
        let monitor = NetworkPathMonitor()
        return network { monitor.connection }
        #else
        return Enricher { _ in }
        #endif
    }

    /// An enricher that sets every record's ``NetworkKey`` to what `connection` returns when the
    /// tracker's worker reaches it, or a destination's delivery does, or sets nothing for `nil`.
    ///
    /// - Parameter connection: The connection now; it runs where the enricher does (the tracker's
    ///   worker, or a destination's delivery), once per record.
    /// - Returns: The enricher.
    package static func network(_ connection: @escaping @Sendable () -> NetworkKey.Value?) -> Enricher {
        Enricher { context in
            if let connection = connection() {
                context[NetworkKey.self] = connection
            }
        }
    }
}
