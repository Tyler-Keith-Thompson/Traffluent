public import Events

/// Where a pipeline delivers events: a plain sink that records what it receives.
public protocol Destination: Sendable {
    /// Records `event`.
    ///
    /// - Parameter event: The event to record.
    func receive(_ event: some Event) async
}
