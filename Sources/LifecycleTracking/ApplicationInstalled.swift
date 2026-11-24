public import Events
public import Persistence

/// The app ran for the first time on this device, at ``version``: what `trackLifecycle` tracks as
/// it starts when its version store holds no version yet.
///
/// It is `BinaryCodable`, so a store keeps it once its `events` list `ApplicationInstalled.self`,
/// and its ``schema`` goes in a tracking plan beside the app's own events.
public struct ApplicationInstalled: Event, BinaryCodable, Hashable {
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

    /// Writes a map of the version (`version`) to `encoder`.
    ///
    /// - Parameter encoder: Where the bytes go.
    public func encode(to encoder: inout BinaryEncoder) {
        encoder.encodeMap { map in
            map.encode(version, forKey: "version")
        }
    }

    /// Reads the version from `decoder`.
    ///
    /// - Parameter decoder: Where the bytes come from.
    /// - Throws: `BinaryDecodingError` when the bytes don't hold a map with a version.
    public init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
        var map = try decoder.decodeMap()
        version = try map.decode(forKey: "version")
    }
}
