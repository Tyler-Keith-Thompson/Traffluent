import Events

/// The event types a store persists, found by type when appending and by name when recovering.
package struct EventRegistry: Sendable {
    /// How one event type is written and read back.
    // A class, so finding one copies a reference rather than its name and both closures.
    package final class Registration: Sendable {
        /// The type's `Event.name`, which each of its records on disk carries.
        package let name: String
        /// The type's `Event.schemaVersion`, which each of its records on disk carries.
        package let version: Int
        /// Writes an event of this type.
        package let encode: @Sendable (any Event, inout BinaryEncoder) -> Void
        /// Reads an event of this type.
        package let decode: @Sendable (inout BinaryDecoder) throws(BinaryDecodingError) -> any Event

        init(
            name: String,
            version: Int,
            encode: @escaping @Sendable (any Event, inout BinaryEncoder) -> Void,
            decode: @escaping @Sendable (inout BinaryDecoder) throws(BinaryDecodingError) -> any Event
        ) {
            self.name = name
            self.version = version
            self.encode = encode
            self.decode = decode
        }
    }

    private let byType: [ObjectIdentifier: Registration]
    private let byName: [String: Registration]

    /// The registry of `types`.
    ///
    /// - Throws: ``DuplicateEventName`` when two of `types` share an `Event.name`, as recovery
    ///   couldn't tell their records apart: one type per event, at its current
    ///   `Event.schemaVersion`. A type listed twice is one type.
    package init(_ types: [any (Event & BinaryCodable).Type]) throws(DuplicateEventName) {
        var byType: [ObjectIdentifier: Registration] = [:]
        var byName: [String: Registration] = [:]
        for type in types {
            let registration = Self.registration(of: type)
            guard byName[registration.name] == nil || byType[ObjectIdentifier(type)] != nil else { throw DuplicateEventName() }
            byType[ObjectIdentifier(type)] = registration
            byName[registration.name] = registration
        }
        self.byType = byType
        self.byName = byName
    }

    /// The registration of `type`, or `nil` when it isn't persisted.
    package func registration(of type: any Event.Type) -> Registration? {
        byType[ObjectIdentifier(type)]
    }

    /// The registration of the type named `name`, or `nil` when none is.
    package func registration(named name: String) -> Registration? {
        byName[name]
    }

    private static func registration<E: Event & BinaryCodable>(of type: E.Type) -> Registration {
        Registration(
            name: E.name,
            version: E.schemaVersion,
            encode: { event, encoder in
                // The registry finds a registration by the event's own type, so the cast holds.
                // Were it to fail, the record's event is written as null, which recovery reports
                // as undecodable, rather than trap in the app.
                guard let event = event as? E else {
                    encoder.write(BinarySimpleValue.null)
                    return
                }
                event.encode(to: &encoder)
            },
            decode: { (decoder: inout BinaryDecoder) throws(BinaryDecodingError) -> any Event in
                try E(from: &decoder)
            }
        )
    }
}

/// The error ``EventRegistry/init(_:)`` throws for two event types that share an `Event.name`.
package struct DuplicateEventName: Error, Hashable, Sendable {
    package init() {}
}
