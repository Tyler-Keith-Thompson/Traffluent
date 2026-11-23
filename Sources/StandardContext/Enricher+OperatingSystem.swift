public import Trackers

extension Enricher {
    /// An enricher that sets every record's ``OperatingSystemKey`` to `operatingSystem`.
    ///
    /// ```swift
    /// let tracker = Tracker(enrichers: [.operatingSystem()])
    /// ```
    ///
    /// The system is read once, when this is called, never per event.
    ///
    /// - Parameter operatingSystem: The system to stamp records with; by default the one the app
    ///   runs on.
    /// - Returns: The enricher, which runs on the tracker's worker like any other.
    public static func operatingSystem(_ operatingSystem: OperatingSystemKey.Value = .current) -> Enricher {
        Enricher { context in
            context[OperatingSystemKey.self] = operatingSystem
        }
    }
}
