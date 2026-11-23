public import Trackers

extension Enricher {
    /// An enricher that sets every record's ``DeviceKey`` to `device`, or sets nothing for `nil`.
    ///
    /// ```swift
    /// let tracker = Tracker(enrichers: [.device()])
    /// ```
    ///
    /// The device is read once, when this is called, never per event.
    ///
    /// - Parameter device: The device to stamp records with; by default the one the app runs on,
    ///   which is `nil` off Apple platforms.
    /// - Returns: The enricher, which runs on the tracker's worker like any other.
    public static func device(_ device: DeviceKey.Value? = .current) -> Enricher {
        Enricher { context in
            if let device {
                context[DeviceKey.self] = device
            }
        }
    }
}
