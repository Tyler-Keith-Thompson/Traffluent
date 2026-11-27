public import Events

/// The app moved to the background: what `trackLifecycle` tracks each time the app leaves the
/// foreground (on macOS, each time it stops being the active app).
///
/// It is `Codable`, so a store keeps it once its `events` list `ApplicationBackgrounded.self`,
/// and its schema goes in a tracking plan beside the app's own events. It has no properties.
public struct ApplicationBackgrounded: Event, Codable, Hashable {
    /// The schema of a move to the background: version 1, collected for analytics, with no properties.
    public static let schema = EventSchema(
        name: name,
        version: schemaVersion,
        consentCategory: consentCategory,
        properties: []
    )

    /// The event for a move to the background.
    public init() {}
}

// The record DiscoveredEvent.all finds this event by, written as @Event writes one: the library's
// own modules don't depend on the macro.
extension ApplicationBackgrounded {
    #if objectFormat(MachO)
        @section("__DATA_CONST,__trfl_events")
    #elseif objectFormat(ELF)
        @section("trfl_events")
    #endif
    @used
    private nonisolated static let __discoveryRecord: __EventDiscovery.Record = (0x6576_6E74, 0, { outValue, type, _, _ in __EventDiscovery.load(ApplicationBackgrounded.self, schema: ApplicationBackgrounded.schema, into: outValue, ofType: type) }, 0, 0)
}
