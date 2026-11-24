public import Events
public import Persistence

/// A session ended, having lasted ``duration``: what `Enricher.sessions(timeout:kinds:)` tracks
/// when an event comes after the timeout's inactivity, before the next session's
/// ``SessionStarted``.
///
/// Its record is stamped with the time of the ended session's last event and carries that
/// session's ``SessionKey``.
///
/// It is `BinaryCodable`, so a store keeps it once its `events` list `SessionEnded.self`, and its
/// ``schema`` goes in a tracking plan beside the app's own events.
public struct SessionEnded: Event, BinaryCodable, Hashable {
    /// The time from the session's first event to its last; zero for a session of one event.
    public var duration: Duration

    /// The schema of a session's end: version 1, collected for analytics, with one property, the
    /// session's duration.
    public static let schema = EventSchema(
        name: name,
        version: 1,
        consentCategory: consentCategory,
        properties: [EventSchema.Property(name: "duration", typeName: "Duration", isOptional: false)]
    )

    /// The event for the end of a session that lasted `duration`.
    ///
    /// - Parameter duration: The time from the session's first event to its last.
    public init(duration: Duration) {
        self.duration = duration
    }

    /// Writes a map of the duration's whole seconds (`seconds`) and its attoseconds
    /// (`attoseconds`) to `encoder`.
    ///
    /// - Parameter encoder: Where the bytes go.
    public func encode(to encoder: inout BinaryEncoder) {
        encoder.encodeMap { map in
            map.encode(duration.components.seconds, forKey: "seconds")
            map.encode(duration.components.attoseconds, forKey: "attoseconds")
        }
    }

    /// Reads the duration's whole seconds and its attoseconds from `decoder`.
    ///
    /// - Parameter decoder: Where the bytes come from.
    /// - Throws: `BinaryDecodingError` when the bytes don't hold a map of two `Int64`s.
    public init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
        var map = try decoder.decodeMap()
        let seconds: Int64 = try map.decode(forKey: "seconds")
        let attoseconds: Int64 = try map.decode(forKey: "attoseconds")
        duration = Duration(secondsComponent: seconds, attosecondsComponent: attoseconds)
    }
}
