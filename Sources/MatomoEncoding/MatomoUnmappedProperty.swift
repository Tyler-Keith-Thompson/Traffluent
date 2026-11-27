/// A property of a tracking plan's event that no custom dimension is mapped to, so Matomo never
/// receives its value.
public struct MatomoUnmappedProperty: Sendable, Hashable {
    /// The event's name.
    public var event: String
    /// The event's schema version.
    public var version: Int
    /// The property's name.
    public var property: String

    /// The property `property` of the event `event` at `version`.
    public init(event: String, version: Int, property: String) {
        self.event = event
        self.version = version
        self.property = property
    }
}
