import Events
import Foundation

/// A record's bytes on disk, the same for every store: its identifier's 16 bytes, its timestamp, `fileID`, `file` (`nil` when
/// it equals `fileID`), function, line, column and event name, then the event's own
/// ``BinaryCodable`` bytes, all in the binary encoding. A record with no call site is written with
/// empty names and line 0, which no call site has, as lines count from 1.
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
        // Line 0 marks a missing call site rather than a flag of its own, so records written
        // before call sites could be missing read the same.
        let location = record.sourceLocation ?? SourceLocation(file: "", fileID: "", function: "", line: 0, column: 0)
        encoder.encode(record.id)
        encoder.encode(record.timestamp)
        encoder.encode(location.fileID)
        encoder.encode(location.file == location.fileID ? nil : location.file)
        encoder.encode(location.function)
        encoder.encode(location.line)
        encoder.encode(location.column)
        encoder.encode(registration.name)
        registration.encode(record.event, &encoder)
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
    ///   or hold bytes past the event's.
    package static func record(from bytes: ArraySlice<UInt8>, registry: EventRegistry) throws(BinaryDecodingError) -> EventRecord {
        var decoder = BinaryDecoder(bytes, readingSensitiveValues: true)
        let id: UUID = try decoder.decode()
        let timestamp: Date = try decoder.decode()
        let fileID: String = try decoder.decode()
        let file: String? = try decoder.decode()
        let function: String = try decoder.decode()
        let line: Int = try decoder.decode()
        let column: Int = try decoder.decode()
        let name: String = try decoder.decode()
        guard let registration = registry.registration(named: name) else { throw .invalidValue }
        let event = try registration.decode(&decoder)
        guard decoder.isAtEnd else { throw .invalidValue }
        let location = line == 0 ? nil : SourceLocation(file: file ?? fileID, fileID: fileID, function: function, line: line, column: column)
        return EventRecord(id: id, event: event, timestamp: timestamp, sourceLocation: location)
    }
}
