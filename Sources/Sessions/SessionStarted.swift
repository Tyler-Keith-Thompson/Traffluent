public import Events

/// A session started: what `Enricher.sessions(timeout:kinds:)` tracks before the first event of
/// each session, stamped with that event's time and carrying the new session's ``SessionKey``.
///
/// It is `Codable`, so a store keeps it once its `events` list `SessionStarted.self`, and
/// its schema goes in a tracking plan beside the app's own events. It has no properties.
public struct SessionStarted: Event, Codable, Hashable {
    /// The schema of a session's start: version 1, collected for analytics, with no properties.
    public static let schema = EventSchema(
        name: name,
        version: schemaVersion,
        consentCategory: consentCategory,
        properties: []
    )

    /// The event for a session's start.
    public init() {}
}

// The record DiscoveredEvent.all finds this event by, written as @Event writes one: the library's
// own modules don't depend on the macro.
extension SessionStarted {
    #if objectFormat(MachO)
        @section("__DATA_CONST,__trfl_events")
    #elseif objectFormat(ELF)
        @section("trfl_events")
    #endif
    @used
    private nonisolated static let __discoveryRecord: __EventDiscovery.Record = (0x6576_6E74, 0, { outValue, type, _, _ in __EventDiscovery.load(SessionStarted.self, schema: SessionStarted.schema, into: outValue, ofType: type) }, 0, 0)
}
