// The macros that write an event's record. Declared here, by a plugin of Traffluent's own, rather
// than taken from LinkerSets: a module that writes records with LinkerSets' @LinkerSetEntry
// depends on LinkerSets and builds its plugin, a second one beside EventMacrosPlugin.

/// Gives an event written by hand the record `@Event` would give it, so
/// ``/Events/DiscoveredEvent/all`` finds it, and conforms it to `__DiscoverableEvent`, the type
/// the record holds it as. An implementation detail of the library's own events: don't use it
/// directly.
///
/// The struct must have a static `schema`; `__DiscoverableEvent` requires one. A generic struct
/// can't be given a record, and is refused.
///
/// The record's unique key is the event's name, the type's, which the macro declares as `name`
/// in an extension of its own: so an app's `@Event` of the same name fails to link beside the
/// library's event, as two `@Event`s of one name do. A static `name` the struct declares itself is
/// an error. In a `private` or `fileprivate` type the record has no key, as `@Event`'s doesn't.
@attached(extension, conformances: __DiscoverableEvent, names: named(name))
@attached(peer)
public macro _DiscoverableEvent() = #externalMacro(module: "EventMacrosPlugin", type: "DiscoverableEventMacro")

/// The record `@Event` and `@_DiscoverableEvent` write beside an event: one LinkerSets record of
/// `kind` whose accessor stores `value`. An implementation detail of their expansions: don't use it
/// directly.
@freestanding(declaration)
public macro __eventRecord<Value>(kind: UInt32, storing value: Value) = #externalMacro(module: "EventMacrosPlugin", type: "EventRecordMacro")
