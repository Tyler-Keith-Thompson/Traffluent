import Events
import Foundation

/// A record's bytes on disk, the same for every store: a CBOR map of its identifier (`id`), its
/// timestamp (`timestamp`), its event type's name (`name`) and `Event.schemaVersion` (`version`),
/// its call site (`sourceLocation`, `null` when the record has none) and its event (`event`), in
/// that order, each in its ``BinaryCodable`` form. The call site is a map of `fileID`, `file`
/// (`null` when it equals `fileID`), `function`, `line` and `column`. Every key is written, `null`
/// for a value there isn't, so a reader finds each in place rather than searching the map for one
/// left out.
///
/// A record without `version` has no version to compare: it is read by its event's name, whatever
/// version the registered type is at, and dropped as undecodable if its bytes don't read.
///
/// A record's context and delivery state are not part of it: a store keeps those, if at all, in a
/// form of its own.
package enum RecordEncoding {
    /// Writes `record`, whose event `registration` encodes, to `encoder`.
    ///
    /// - Parameters:
    ///   - record: The record to write.
    ///   - registration: The registration of the record's event type.
    ///   - encoder: Where the bytes go.
    package static func encode(_ record: EventRecord, registration: EventRegistry.Registration, to encoder: inout BinaryEncoder) {
        encoder.encodeMap { map in
            map.encode(record.id, forKey: "id")
            map.encode(record.timestamp, forKey: "timestamp")
            map.encode(registration.name, forKey: "name")
            map.encode(registration.version, forKey: "version")
            if let location = record.sourceLocation {
                // The map itself, with no copy of the location: a map's head is neither `null`
                // nor an optional's wrapper, so these are the bytes the optional would write.
                map.encode(forKey: "sourceLocation") { StoredSourceLocation.encode(location, to: &$0) }
            } else {
                map.encode(StoredSourceLocation?.none, forKey: "sourceLocation")
            }
            map.encode(forKey: "event") { registration.encode(record.event, &$0) }
        }
    }

    /// The bytes of `record`, whose event `registration` encodes.
    ///
    /// - Parameters:
    ///   - record: The record to write.
    ///   - registration: The registration of the record's event type.
    /// - Returns: The record's bytes.
    package static func bytes(of record: EventRecord, registration: EventRegistry.Registration) -> [UInt8] {
        var encoder = BinaryEncoder(writingSensitiveValues: true)
        encode(record, registration: registration, to: &encoder)
        return encoder.takeBytes()
    }

    /// What reading a record's bytes found: the record, or a record of a registered event type
    /// stored at another version than the type's, which is left undecoded.
    package enum Reading {
        /// The record, with its identifier, no tag, tracked in the top-level context.
        case record(EventRecord)
        /// A record of the event named `event`, stored at `storedVersion` while its registered type
        /// is at `currentVersion`.
        case versionMismatch(event: String, storedVersion: Int, currentVersion: Int)
    }

    /// The record `bytes` hold, decoded through `registry`, or the versions that kept it from
    /// being decoded.
    ///
    /// - Parameters:
    ///   - bytes: A record's bytes, as ``encode(_:registration:to:)`` wrote them.
    ///   - registry: The event types the store keeps.
    /// - Returns: The record, or ``Reading/versionMismatch(event:storedVersion:currentVersion:)``
    ///   when it holds a version that isn't its registered type's.
    /// - Throws: ``BinaryDecodingError`` when the bytes aren't a record of a registered event type,
    ///   or hold bytes past the record's map.
    package static func record(from bytes: ArraySlice<UInt8>, registry: EventRegistry) throws(BinaryDecodingError) -> Reading {
        var decoder = BinaryDecoder(bytes, readingSensitiveValues: true)
        var map = try decoder.decodeMap()
        guard decoder.isAtEnd else { throw .invalidValue }
        let id: UUID = try map.decode(forKey: "id")
        let timestamp: Date = try map.decode(forKey: "timestamp")
        let name: String = try map.decode(forKey: "name")
        let version: Int? = try map.decode(forKey: "version")
        guard let registration = registry.registration(named: name) else { throw .invalidValue }
        // Checked before the event is read: a version raised for a change whose bytes would still
        // decode, such as a property whose meaning changed, must not be read as the new one.
        if let version, version != registration.version {
            return .versionMismatch(event: name, storedVersion: version, currentVersion: registration.version)
        }
        let location: StoredSourceLocation? = try map.decode(forKey: "sourceLocation")
        guard var eventDecoder = try map.decoder(forKey: "event") else { throw .keyNotFound }
        let event = try registration.decode(&eventDecoder)
        return .record(EventRecord(id: id, event: event, timestamp: timestamp, sourceLocation: location?.location))
    }
}

/// A record's call site in its ``BinaryCodable`` form: a map, its file `null` when it equals
/// its file ID, as it does unless `#filePath` was passed.
private struct StoredSourceLocation: BinaryCodable {
    let location: SourceLocation

    init(location: SourceLocation) {
        self.location = location
    }

    func encode(to encoder: inout BinaryEncoder) {
        Self.encode(location, to: &encoder)
    }

    /// Writes `location` as a stored call site.
    static func encode(_ location: SourceLocation, to encoder: inout BinaryEncoder) {
        encoder.encodeMap { map in
            map.encode(location.fileID, forKey: "fileID")
            map.encode(location.file == location.fileID ? nil : location.file, forKey: "file")
            map.encode(location.function, forKey: "function")
            map.encode(location.line, forKey: "line")
            map.encode(location.column, forKey: "column")
        }
    }

    init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
        var map = try decoder.decodeMap()
        let fileID: String = try map.decode(forKey: "fileID")
        let file: String? = try map.decode(forKey: "file")
        location = SourceLocation(
            file: file ?? fileID,
            fileID: fileID,
            function: try map.decode(forKey: "function"),
            line: try map.decode(forKey: "line"),
            column: try map.decode(forKey: "column")
        )
    }
}
