public import Events

/// Every event tracked while `withRecordingTracker` ran its body, in the order tracked, with what
/// the body returned.
///
/// ```swift
/// let tracked = await withRecordingTracker {
///     Tracker.current.track(SignedUp(plan: "pro"))
/// }
/// #expect(tracked.events(of: SignedUp.self) == [SignedUp(plan: "pro")])
/// ```
public struct TrackerRecording<Value> {
    /// What the body returned.
    public let value: Value

    /// The record of each event tracked, in the order tracked, with its timestamp, source
    /// location and context.
    public let records: [EventRecord]

    init(value: Value, records: [EventRecord]) {
        self.value = value
        self.records = records
    }

    /// The name of each event tracked, in the order tracked, whatever its type.
    ///
    /// - Complexity: O(*n*), where *n* is the number of records.
    public var names: [String] {
        records.map(\.name)
    }

    /// The events of type `type` tracked, in the order tracked; events of other types are left
    /// out.
    ///
    /// - Parameter type: The event type to read.
    /// - Returns: Each tracked event of that type, as that type.
    /// - Complexity: O(*n*), where *n* is the number of records.
    public func events<E: Event>(of type: E.Type) -> [E] {
        records.compactMap { $0.event as? E }
    }
}

extension TrackerRecording: Sendable where Value: Sendable {}
