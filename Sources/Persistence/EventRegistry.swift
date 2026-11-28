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
        /// Writes an event of this type under `key`.
        package let encode: @Sendable (any Event, _ key: RecordEncoding.Key, inout KeyedEncodingContainer<RecordEncoding.Key>) throws -> Void
        /// Reads an event of this type from under `key`.
        package let decode: @Sendable (_ key: RecordEncoding.Key, KeyedDecodingContainer<RecordEncoding.Key>) throws -> any Event

        init(
            name: String,
            version: Int,
            encode: @escaping @Sendable (any Event, _ key: RecordEncoding.Key, inout KeyedEncodingContainer<RecordEncoding.Key>) throws -> Void,
            decode: @escaping @Sendable (_ key: RecordEncoding.Key, KeyedDecodingContainer<RecordEncoding.Key>) throws -> any Event
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
    package init(_ types: [any (Event & Codable).Type]) throws(DuplicateEventName) {
        var byType: [ObjectIdentifier: Registration] = [:]
        var byName: [String: Registration] = [:]
        // The type that registered each name, so a clash names both types.
        var typeByName: [String: any (Event & Codable).Type] = [:]
        for type in types {
            let registration = Self.registration(of: type)
            if let registered = typeByName[registration.name], ObjectIdentifier(registered) != ObjectIdentifier(type) {
                throw DuplicateEventName(name: registration.name, firstType: String(reflecting: registered), secondType: String(reflecting: type))
            }
            byType[ObjectIdentifier(type)] = registration
            byName[registration.name] = registration
            typeByName[registration.name] = type
        }
        self.byType = byType
        self.byName = byName
    }

    /// The registry of the newest version of each event in `types`: of the types that share an
    /// `Event.name`, only the one at the highest `Event.schemaVersion`.
    ///
    /// The list-free stores take this from `DiscoveredEvent.all`, where a program that reads an
    /// event's earlier versions, such as a relay reading older apps' batches, declares a type of
    /// each version. A store writes only what the program tracks now, the newest version, and a
    /// record stored at an earlier one is dropped as a version mismatch, as it would be were the
    /// earlier types gone.
    ///
    /// - Throws: ``DuplicateEventName`` when two of `types` share an `Event.name` and an
    ///   `Event.schemaVersion`, at any version, the highest or not, as nothing tells which of
    ///   the two is meant. A type listed twice is one type.
    /// - Complexity: O(*n*) in the types.
    package init(newestVersionsOf types: [any (Event & Codable).Type]) throws(DuplicateEventName) {
        // The newest version, as a store writes what the program tracks now. Two alternatives
        // were turned down. Keeping every version, a registration per name and version, would
        // read a record stored before an upgrade through its earlier type and deliver it; but
        // records are never migrated (D9), an explicit list still holds one type per name, and
        // recovery would hand destinations a version the app no longer tracks. Keeping the
        // lowest would leave the events tracked now unwritten (notPersisted, lost if the app ends).
        var newest: [String: any (Event & Codable).Type] = [:]
        // The type that took each name and version, so a clash at any version names both types.
        var typeByVersion: [NameAndVersion: any (Event & Codable).Type] = [:]
        for type in types {
            let key = NameAndVersion(name: type.name, version: type.schemaVersion)
            if let registered = typeByVersion[key], ObjectIdentifier(registered) != ObjectIdentifier(type) {
                throw DuplicateEventName(name: key.name, firstType: String(reflecting: registered), secondType: String(reflecting: type))
            }
            typeByVersion[key] = type
            if newest[key.name].map({ $0.schemaVersion < key.version }) ?? true {
                newest[key.name] = type
            }
        }
        try self.init(types.filter { type in newest[type.name].map { ObjectIdentifier($0) == ObjectIdentifier(type) } ?? false })
    }

    /// The registration of `type`, or `nil` when it isn't persisted.
    package func registration(of type: any Event.Type) -> Registration? {
        byType[ObjectIdentifier(type)]
    }

    /// The registration of the type named `name`, or `nil` when none is.
    package func registration(named name: String) -> Registration? {
        byName[name]
    }

    private static func registration<E: Event & Codable>(of type: E.Type) -> Registration {
        Registration(
            name: E.name,
            version: E.schemaVersion,
            encode: { event, key, container in
                // The registry finds a registration by the event's own type, so the cast holds.
                // Were it to fail, the record's event is written as null, which recovery reports
                // as undecodable, rather than trap in the app.
                guard let event = event as? E else {
                    try container.encodeNil(forKey: key)
                    return
                }
                try container.encode(event, forKey: key)
            },
            decode: { key, container in
                try container.decode(E.self, forKey: key)
            }
        )
    }
}

/// An event's name and version, which no two of the types ``EventRegistry/init(newestVersionsOf:)``
/// takes may share.
private struct NameAndVersion: Hashable {
    let name: String
    let version: Int
}

/// The error ``EventRegistry/init(_:)`` throws for two event types that share an `Event.name`, and
/// ``EventRegistry/init(newestVersionsOf:)`` for two that share a name and a version.
package struct DuplicateEventName: Error, Hashable, Sendable {
    /// The name both types share.
    package let name: String
    /// The fully qualified name of the type listed first.
    package let firstType: String
    /// The fully qualified name of the type listed second.
    package let secondType: String
}
