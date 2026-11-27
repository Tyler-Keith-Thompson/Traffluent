public import Events

/// The app ran for the first time at ``version`` after running at ``previousVersion``: what
/// `trackLifecycle` tracks as it starts when its version store holds another version.
///
/// It is `Codable`, so a store keeps it once its `events` list `ApplicationUpdated.self`,
/// and its ``schema`` goes in a tracking plan beside the app's own events.
public struct ApplicationUpdated: Event, Codable, Hashable {
    /// The version the app ran at before.
    public var previousVersion: String

    /// The version the app runs at now.
    public var version: String

    /// The schema of an update: version 1, collected for analytics, with two properties, the
    /// previous version and the new one.
    public static let schema = EventSchema(
        name: name,
        version: schemaVersion,
        consentCategory: consentCategory,
        properties: [
            EventSchema.Property(name: "previousVersion", typeName: "String", isOptional: false),
            EventSchema.Property(name: "version", typeName: "String", isOptional: false),
        ]
    )

    /// The event for an update from `previousVersion` to `version`.
    ///
    /// - Parameters:
    ///   - previousVersion: The version the app ran at before.
    ///   - version: The version the app runs at now.
    public init(previousVersion: String, version: String) {
        self.previousVersion = previousVersion
        self.version = version
    }
}

// The record DiscoveredEvent.all finds this event by, written as @Event writes one: the library's
// own modules don't depend on the macro.
extension ApplicationUpdated {
    #if objectFormat(MachO)
        @section("__DATA_CONST,__trfl_events")
    #elseif objectFormat(ELF)
        @section("trfl_events")
    #endif
    @used
    private nonisolated static let __discoveryRecord: __EventDiscovery.Record = (0x6576_6E74, 0, { outValue, type, _, _ in __EventDiscovery.load(ApplicationUpdated.self, schema: ApplicationUpdated.schema, into: outValue, ofType: type) }, 0, 0)
}
