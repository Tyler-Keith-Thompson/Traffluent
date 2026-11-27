public import Events
internal import LinkerSets

/// A session ended, having lasted ``duration``: what `Enricher.sessions(timeout:kinds:)` tracks
/// when an event comes after the timeout's inactivity, before the next session's
/// ``SessionStarted``.
///
/// Its record is stamped with the time of the ended session's last event and carries that
/// session's ``SessionKey``.
///
/// It is `Codable`, so a store keeps it once its `events` list `SessionEnded.self`, and its
/// ``schema`` goes in a tracking plan beside the app's own events.
public struct SessionEnded: Event, Codable, Hashable {
    /// The time from the session's first event to its last; zero for a session of one event.
    public var duration: Duration

    /// The schema of a session's end: version 1, collected for analytics, with one property, the
    /// session's duration.
    public static let schema = EventSchema(
        name: name,
        version: schemaVersion,
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
    /// - Parameter encoder: Where the duration goes.
    /// - Throws: What the encoder throws.
    public func encode(to encoder: any Encoder) throws {
        // Its components by name rather than `Duration`'s own conformance, an array of two
        // integers that aren't its seconds, so a reader of the bytes finds the seconds.
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(duration.components.seconds, forKey: .seconds)
        try container.encode(duration.components.attoseconds, forKey: .attoseconds)
    }

    /// Reads the duration's whole seconds and its attoseconds from `decoder`.
    ///
    /// - Parameter decoder: Where the duration comes from.
    /// - Throws: `DecodingError` when the decoder doesn't hold a map of two `Int64`s.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        duration = Duration(
            secondsComponent: try container.decode(Int64.self, forKey: .seconds),
            attosecondsComponent: try container.decode(Int64.self, forKey: .attoseconds)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case seconds
        case attoseconds
    }
}

// The record DiscoveredEvent.all finds this event by, of the kind and type @Event's records have:
// the library's own modules don't depend on the macro.
extension SessionEnded: __DiscoverableEvent {
    @LinkerSetEntry(kind: 0x6576_6E74)  // "evnt", the kind Events reads; everyEvent checks it
    private static let discoveryRecord: any __DiscoverableEvent.Type = SessionEnded.self
}
