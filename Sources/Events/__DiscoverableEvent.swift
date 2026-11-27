/// An event ``DiscoveredEvent/all`` can find: the type its record in the binary holds. An
/// implementation detail of `@Event`, which conforms each struct it gives a record to: don't use it
/// directly.
///
/// The record is a LinkerSets record of Traffluent's event kind whose value is the event's type,
/// as an `any __DiscoverableEvent.Type`, which carries the type's ``schema`` to the reader.
// A protocol of the library's own rather than `any (Event & Codable).Type`: Event has no schema
// requirement, and a record holds one value, the type. Underscored, as `@Event` adds it to every
// struct it expands, and nothing else should name it.
public protocol __DiscoverableEvent: Event, Codable {
    /// The event's schema.
    static var schema: EventSchema { get }
}
