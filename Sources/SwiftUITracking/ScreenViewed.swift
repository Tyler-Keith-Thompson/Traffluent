public import Events

/// Someone viewed the screen named ``screen``: what `trackScreen(_:)` tracks each time its view
/// appears.
///
/// It is `Codable`, so a store keeps it once its `events` list `ScreenViewed.self`, and its
/// ``schema`` goes in a tracking plan beside the app's own events. It builds on every platform, so
/// a tracking plan or a collector off Apple platforms can name it too.
public struct ScreenViewed: Event, Codable, Hashable {
    /// The viewed screen's name.
    public var screen: String

    /// The schema of a screen view: version 1, collected for analytics, with one property, the
    /// screen's name.
    public static let schema = EventSchema(
        name: name,
        version: schemaVersion,
        consentCategory: consentCategory,
        properties: [EventSchema.Property(name: "screen", typeName: "String", isOptional: false)]
    )

    /// The event for a view of the screen named `screen`.
    ///
    /// - Parameter screen: The viewed screen's name.
    public init(screen: String) {
        self.screen = screen
    }
}
