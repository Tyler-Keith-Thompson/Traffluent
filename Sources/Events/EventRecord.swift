public import Foundation
public import Instrumentation

/// A tracked event: the event itself, when it was tracked, where, and the context it was tracked in.
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
    /// The `ServiceContext` the event was tracked in, with what the pipeline's enrichers added.
    ///
    /// Its values are read through typed `ServiceContextKey`s. Inside an active span, it holds the
    /// span's context, so a destination can join the event to the trace.
    public var context: ServiceContext

    /// A record of `event`, tracked at `timestamp` from `sourceLocation` in `context`.
    ///
    /// - Parameters:
    ///   - event: The event that was tracked.
    ///   - timestamp: When the event was tracked.
    ///   - sourceLocation: Where in source code the event was tracked.
    ///   - context: The context the event was tracked in; none by default.
    public init(event: any Event, timestamp: Date, sourceLocation: SourceLocation, context: ServiceContext = .topLevel) {
        self.event = event
        self.timestamp = timestamp
        self.sourceLocation = sourceLocation
        self.context = context
    }

    /// The name the event is recorded under: its type's `Event.name`.
    public var name: String {
        type(of: event).name
    }
}
