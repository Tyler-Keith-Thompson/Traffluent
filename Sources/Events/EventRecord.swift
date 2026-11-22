public import Foundation

/// A tracked event: the event itself, when it was tracked, and where.
///
/// A pipeline makes one record per tracked event and delivers them to its destinations in
/// batches. The event keeps its type: a destination reads its properties by casting
/// ``event`` to the event types it knows, or by opening it as `some Event`.
public struct EventRecord: Sendable {
    /// The event that was tracked.
    public var event: any Event
    /// When the event was tracked.
    public var timestamp: Date
    /// Where in source code the event was tracked.
    public var sourceLocation: SourceLocation

    /// A record of `event`, tracked at `timestamp` from `sourceLocation`.
    ///
    /// - Parameters:
    ///   - event: The event that was tracked.
    ///   - timestamp: When the event was tracked.
    ///   - sourceLocation: Where in source code the event was tracked.
    public init(event: any Event, timestamp: Date, sourceLocation: SourceLocation) {
        self.event = event
        self.timestamp = timestamp
        self.sourceLocation = sourceLocation
    }

    /// The name the event is recorded under: its type's `Event.name`.
    public var name: String {
        type(of: event).name
    }
}
