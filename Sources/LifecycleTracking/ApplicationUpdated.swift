public import Events
public import Persistence

/// The app ran for the first time at ``version`` after running at ``previousVersion``: what
/// `trackLifecycle` tracks as it starts when its version store holds another version.
///
/// It is `BinaryCodable`, so a store keeps it once its `events` list `ApplicationUpdated.self`,
/// and its ``schema`` goes in a tracking plan beside the app's own events.
public struct ApplicationUpdated: Event, BinaryCodable, Hashable {
    /// The version the app ran at before.
    public var previousVersion: String

    /// The version the app runs at now.
    public var version: String

    /// The schema of an update: version 1, collected for analytics, with two properties, the
    /// previous version and the new one.
    public static let schema = EventSchema(
        name: name,
        version: 1,
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

    /// Writes the previous version, then the new one, to `encoder`.
    ///
    /// - Parameter encoder: Where the bytes go.
    public func encode(to encoder: inout BinaryEncoder) {
        encoder.encode(previousVersion)
        encoder.encode(version)
    }

    /// Reads the previous version, then the new one, from `decoder`.
    ///
    /// - Parameter decoder: Where the bytes come from.
    /// - Throws: `BinaryDecodingError` when the bytes don't hold two versions.
    public init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
        previousVersion = try decoder.decode()
        version = try decoder.decode()
    }
}
