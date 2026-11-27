internal import LinkerSetsRuntime

extension LinkerSetKind {
    /// The kind of the records of event types, `"evnt"`: `@Event`'s (`EventMacro.kind(of:)` in the
    /// plugin) and the library's own (`@LinkerSetEntry(kind:)` beside each), which
    /// ``DiscoveredEvent/all`` reads.
    // Internal, so `import Traffluent` adds no member to LinkerSetsRuntime's type. The number is
    // written out in each of those places, as the macro and the attribute take a literal; nothing
    // but DiscoveredEventTests' everyEvent, which lists both kinds of event, catches one that
    // drifts. Another library's records of this kind are skipped: they don't hold an `any
    // __DiscoverableEvent.Type`.
    static let events = LinkerSetKind(rawValue: 0x6576_6E74)
}
