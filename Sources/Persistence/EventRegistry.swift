import Events

/// The event types a store persists, found by type when appending and by name when recovering.
package struct EventRegistry: Sendable {
    /// How one event type is written and read back.
    package struct Registration: Sendable {
        /// The type's `Event.name`, which each of its records on disk carries.
        package let name: String
        /// Writes an event of this type.
        package let encode: @Sendable (any Event, inout BinaryEncoder) -> Void
        /// Reads an event of this type.
        package let decode: @Sendable (inout BinaryDecoder) throws(BinaryDecodingError) -> any Event
    }

    private let byType: [ObjectIdentifier: Registration]
    private let byName: [String: Registration]

    /// The registry of `types`.
    ///
    /// - Precondition: No two of `types` share an `Event.name`.
    package init(_ types: [any (Event & BinaryCodable).Type]) {
        var byType: [ObjectIdentifier: Registration] = [:]
        var byName: [String: Registration] = [:]
        for type in types {
            let registration = Self.registration(of: type)
            // A trap rather than an error: two types under one name is a programming mistake,
            // and recovery couldn't tell their records apart.
            precondition(byName[registration.name] == nil || byType[ObjectIdentifier(type)] != nil, "Two persisted event types share the name \(registration.name); give one an explicit Event.name")
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
            encode: { event, encoder in
                // The registry finds a registration by the event's own type, so the cast holds.
                (event as! E).encode(to: &encoder)
            },
            decode: { (decoder: inout BinaryDecoder) throws(BinaryDecodingError) -> any Event in
                try E(from: &decoder)
            }
        )
    }
}
