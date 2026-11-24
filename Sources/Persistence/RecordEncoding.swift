import Events
import Foundation

/// A record's bytes on disk, the same for every store: a CBOR map of its identifier (`id`), its
/// timestamp (`timestamp`), its event type's name (`name`), its call site (`sourceLocation`, `null`
/// when the record has none) and its event (`event`), in that order, each in its
/// ``BinaryCodable`` form. The call site is a map of `fileID`, `file` (`null` when it equals
/// `fileID`), `function`, `line` and `column`. Every key is written, `null` for a value there
/// isn't, so a reader finds each in place rather than searching the map for one left out.
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
            map.encode(record.sourceLocation.map(StoredSourceLocation.init(location:)), forKey: "sourceLocation")
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
        return encoder.bytes
    }

    /// The record `bytes` hold, decoded through `registry`: a record with its identifier, no tag,
    /// tracked in the top-level context.
    ///
    /// - Parameters:
    ///   - bytes: A record's bytes, as ``encode(_:registration:to:)`` wrote them.
    ///   - registry: The event types the store keeps.
    /// - Returns: The record.
    /// - Throws: ``BinaryDecodingError`` when the bytes aren't a record of a registered event type,
    ///   or hold bytes past the record's map.
    package static func record(from bytes: ArraySlice<UInt8>, registry: EventRegistry) throws(BinaryDecodingError) -> EventRecord {
        var decoder = BinaryDecoder(bytes, readingSensitiveValues: true)
        var map = try decoder.decodeMap()
        guard decoder.isAtEnd else { throw .invalidValue }
        let id: UUID = try map.decode(forKey: "id")
        let timestamp: Date = try map.decode(forKey: "timestamp")
        let name: String = try map.decode(forKey: "name")
        let location: StoredSourceLocation? = try map.decode(forKey: "sourceLocation")
        guard let registration = registry.registration(named: name) else { throw .invalidValue }
        guard var eventDecoder = try map.decoder(forKey: "event") else { throw .keyNotFound }
        let event = try registration.decode(&eventDecoder)
        return EventRecord(id: id, event: event, timestamp: timestamp, sourceLocation: location?.location)
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
