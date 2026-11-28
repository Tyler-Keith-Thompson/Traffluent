public import Events
internal import EventMacros

/// The app is about to end: what `trackLifecycle` tracks where the platform reports it (on iOS,
/// iPadOS, tvOS, visionOS and macOS, as the app terminates), and as its `finish()` is called.
///
/// It is `Codable`, so a store keeps it once its `events` list `ApplicationTerminated.self`,
/// and its schema goes in a tracking plan beside the app's own events. It has no properties.
@_DiscoverableEvent
public struct ApplicationTerminated: Event, Codable, Hashable {
    /// The schema of an end: version 1, collected for analytics, with no properties.
    public static let schema = EventSchema(
        name: name,
        version: schemaVersion,
        consentCategory: consentCategory,
        properties: []
    )

    /// The event for an end.
    public init() {}
}
