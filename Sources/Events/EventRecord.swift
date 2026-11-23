public import Foundation
public import Instrumentation

/// A tracked event: the event itself, when it was tracked, where, and the context it was tracked in.
///
/// A tracker makes one record per tracked event, and a delivery hands them to its destinations
/// in batches. The event keeps its type: a destination reads its properties by casting
/// ``event`` to the event types it knows, or by opening it as `some Event`.
public struct EventRecord: Sendable {
    /// The event that was tracked.
    public var event: any Event
    /// When the event was tracked.
    public var timestamp: Date
    /// Where in source code the event was tracked.
    public var sourceLocation: SourceLocation
    /// The `ServiceContext` the event was tracked in, with what the tracker's enrichers added.
    ///
    /// Its values are read through typed `ServiceContextKey`s. Inside an active span, it holds the
    /// span's context, so a destination can join the event to the trace.
    public var context: ServiceContext
    /// Whether the record may have reached a destination before: it was handed to a delivery in an
    /// earlier run of the app, which ended before the delivery was acknowledged.
    ///
    /// A destination that must not count an event twice uses it to deduplicate. A record tracked
    /// in this run is never redelivered.
    public var isRedelivered: Bool
    /// The store keeping the record until it is delivered, and the record's place in it; `nil` for
    /// a record kept in memory only.
    ///
    /// A store sets it when it keeps the record, and `deliver(to:)` tells the store through it
    /// when the record is about to be delivered and once it has been.
    public var deliveryTag: DeliveryTag?

    /// A record of `event`, tracked at `timestamp` from `sourceLocation` in `context`.
    ///
    /// - Parameters:
    ///   - event: The event that was tracked.
    ///   - timestamp: When the event was tracked.
    ///   - sourceLocation: Where in source code the event was tracked.
    ///   - context: The context the event was tracked in; none by default.
    ///   - isRedelivered: Whether the record may have been delivered in an earlier run; `false` by
    ///     default.
    ///   - deliveryTag: Where a store keeps the record; `nil`, memory only, by default.
    public init(
        event: any Event,
        timestamp: Date,
        sourceLocation: SourceLocation,
        context: ServiceContext = .topLevel,
        isRedelivered: Bool = false,
        deliveryTag: DeliveryTag? = nil
    ) {
        self.event = event
        self.timestamp = timestamp
        self.sourceLocation = sourceLocation
        self.context = context
        self.isRedelivered = isRedelivered
        self.deliveryTag = deliveryTag
    }

    /// The name the event is recorded under: its type's `Event.name`.
    public var name: String {
        type(of: event).name
    }
}
