public import Events
internal import EventMacros

/// The app ran for the first time on this device, at ``version``: what `trackLifecycle` tracks as
/// it starts when its version store holds no version yet.
///
/// It is `Codable`, so a store keeps it once its `events` list `ApplicationInstalled.self`,
/// and its ``schema`` goes in a tracking plan beside the app's own events.
@_DiscoverableEvent
public struct ApplicationInstalled: Event, Codable, Hashable {
    /// The version installed.
    public var version: String

    /// The schema of an install: version 1, collected for analytics, with one property, the
    /// version installed.
    public static let schema = EventSchema(
        name: name,
        version: schemaVersion,
        consentCategory: consentCategory,
        properties: [EventSchema.Property(name: "version", typeName: "String", isOptional: false)]
    )

    /// The event for an install of `version`.
    ///
    /// - Parameter version: The version installed.
    public init(version: String) {
        self.version = version
    }
}
