public import Events
internal import EventMacros

/// A session started: what `Enricher.sessions(timeout:kinds:)` tracks before the first event of
/// each session, stamped with that event's time and carrying the new session's ``/Events/SessionKey``.
///
/// It is `Codable`, so a store keeps it once its `events` list `SessionStarted.self`, and
/// its schema goes in a tracking plan beside the app's own events. It has no properties.
@_DiscoverableEvent
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
