public import Events
internal import EventMacros

/// The app was opened: launched, or brought back to the foreground when ``fromBackground``. What
/// `trackLifecycle` tracks as it starts, and each time the app returns from the background.
///
/// It is `Codable`, so a store keeps it once its `events` list `ApplicationOpened.self`,
/// and its ``schema`` goes in a tracking plan beside the app's own events.
@_DiscoverableEvent
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
