internal import LinkerSetsRuntime

extension LinkerSetKind {
    /// The kind of the records of event types, `"evnt"`: those `@Event` and `@_DiscoverableEvent`
    /// write (`EventLinkerSetMacro.kind(of:)` in the plugin), which ``DiscoveredEvent/all`` reads.
    // Internal, so `import Traffluent` adds no member to LinkerSetsRuntime's type. The number is
    // written here and once in the plugin, which depends on packages' products only and so can't
    // read it from this module; DiscoveredEventTests' everyEvent, which lists events of both
    // macros, fails when the two drift, as no event would then be found. Another library's records
    // of this kind are skipped: they don't hold an `any __DiscoverableEvent.Type`.
    static let events = LinkerSetKind(rawValue: 0x6576_6E74)
}
