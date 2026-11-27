public import Events

/// The app was opened: launched, or brought back to the foreground when ``fromBackground``. What
/// `trackLifecycle` tracks as it starts, and each time the app returns from the background.
///
/// It is `Codable`, so a store keeps it once its `events` list `ApplicationOpened.self`,
/// and its ``schema`` goes in a tracking plan beside the app's own events.
public struct ApplicationOpened: Event, Codable, Hashable {
    /// Whether the app came back from the background, rather than being launched.
    public var fromBackground: Bool

    /// The schema of an open: version 1, collected for analytics, with one property, whether the
    /// app came back from the background.
    public static let schema = EventSchema(
        name: name,
        version: schemaVersion,
        consentCategory: consentCategory,
        properties: [EventSchema.Property(name: "fromBackground", typeName: "Bool", isOptional: false)]
    )

    /// The event for an open, from the background or not.
    ///
    /// - Parameter fromBackground: Whether the app came back from the background.
    public init(fromBackground: Bool) {
        self.fromBackground = fromBackground
    }
}

// The record DiscoveredEvent.all finds this event by, written as @Event writes one: the library's
// own modules don't depend on the macro.
extension ApplicationOpened {
    #if objectFormat(MachO)
        @section("__DATA_CONST,__trfl_events")
    #elseif objectFormat(ELF)
        @section("trfl_events")
    #endif
    @used
    private nonisolated static let __discoveryRecord: __EventDiscovery.Record = (0x6576_6E74, 0, { outValue, type, _, _ in __EventDiscovery.load(ApplicationOpened.self, schema: ApplicationOpened.schema, into: outValue, ofType: type) }, 0, 0)
}
