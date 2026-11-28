internal import CBOR
public import Events
import Foundation
import Instrumentation

/// A record's bytes on disk, the same for every store: a CBOR map, written by the CBOR package's
/// `CBOREncoder` with its keys sorted, of its identifier (`id`, its UUID string), its timestamp
/// (`timestamp`, a double of its seconds since 2001-01-01 UTC, which `Date` stores, so it reads
/// back exactly), its event type's name (`name`) and `Event.schemaVersion` (`version`), its call
/// site (`sourceLocation`, left out when the record has none), its session (`session`, the
/// `SessionKey` of its context as a UUID string, left out when it has none) and its event
/// (`event`, written by its `Codable` conformance). The call site is a map of `fileID`, `file`
/// (left out when it equals `fileID`), `function`, `line` and `column`.
///
/// A record without `version` has no version to compare: it is read by its event's name, whatever
/// version the registered type is at, and dropped as undecodable if its bytes don't read. A record
/// without `session` is read back with none, and one whose `session` isn't a UUID string, null
/// included, is undecodable.
///
/// The session is the only part of a record's context kept, and only here, beside the record, so
/// it is deleted with the record's bytes. The rest of the context and the delivery state are not
/// part of it: a store keeps the delivery state in a form of its own.
package enum RecordEncoding {
    /// A record map's keys.
    package enum Key: String, CodingKey {
        case id
        case timestamp
        case name
        case version
        case sourceLocation
        case session
        case event
    }

    /// The bytes of `record`, whose event `registration` encodes, with its `Sensitive` values
    /// written as themselves.
    ///
    /// - Parameters:
    ///   - record: The record to write.
    ///   - registration: The registration of the record's event type.
    /// - Returns: The record's bytes.
    /// - Throws: What the event's `encode(to:)` throws.
    package static func bytes(of record: EventRecord, registration: EventRegistry.Registration) throws -> [UInt8] {
        try SensitiveCoding.$revealsValues.withValue(true) {
            try CBOREncoder().encode(StoredRecord(record: record, registration: registration))
        }
    }

    /// What reading a record's bytes found: the record, or a record of a registered event type
    /// stored at another version than the type's, which is left undecoded.
    package enum Reading {
        /// The record, with its identifier and no tag, tracked in the top-level context with its
        /// session's `SessionKey` set, when it had one.
        case record(EventRecord)
        /// A record of the event named `event`, stored at `storedVersion` while its registered type
        /// is at `currentVersion`.
        case versionMismatch(event: String, storedVersion: Int, currentVersion: Int)
    }

    /// The record `bytes` hold, decoded through `registry`, or the versions that kept it from
    /// being decoded.
    ///
    /// - Parameters:
    ///   - bytes: A record's bytes, as ``bytes(of:registration:)`` wrote them.
    ///   - registry: The event types the store keeps.
    /// - Returns: The record, or ``Reading/versionMismatch(event:storedVersion:currentVersion:)``
    ///   when it holds a version that isn't its registered type's.
    /// - Throws: `CBORError` when the bytes aren't one CBOR data item, or `DecodingError` when they
    ///   aren't a record of a registered event type.
    package static func record(from bytes: ArraySlice<UInt8>, registry: EventRegistry) throws -> Reading {
        try SensitiveCoding.$revealsValues.withValue(true) {
            // The decoder itself, kept past its initializer, so the event's type can be looked up
            // by the record's name before the event is read, in one parse of the bytes.
            let decoder = try CBORDecoder().decode(DecoderReference.self, from: bytes).decoder
            let container = try decoder.container(keyedBy: Key.self)
            let name = try container.decode(String.self, forKey: .name)
            guard let registration = registry.registration(named: name) else {
                throw DecodingError.dataCorruptedError(forKey: .name, in: container, debugDescription: "No event type of the store has this name.")
            }
            // Checked before the event is read: a version raised for a change whose bytes would
            // still decode, such as a property whose meaning changed, must not be read as the new
            // one.
            if let version = try container.decodeIfPresent(Int.self, forKey: .version), version != registration.version {
                return .versionMismatch(event: name, storedVersion: version, currentVersion: registration.version)
            }
            let id = try container.decode(UUID.self, forKey: .id)
            let timestamp = Date(timeIntervalSinceReferenceDate: try container.decode(Double.self, forKey: .timestamp))
            let location = try container.decodeIfPresent(StoredSourceLocation.self, forKey: .sourceLocation)
            var context = ServiceContext.topLevel
            // decode, not decodeIfPresent, which would read a null session as none: a session that is
            // there but isn't a UUID string, null included, makes the record undecodable.
            if container.contains(.session) {
                context[SessionKey.self] = try container.decode(UUID.self, forKey: .session)
            }
            let event = try registration.decode(.event, container)
            return .record(EventRecord(id: id, event: event, timestamp: timestamp, sourceLocation: location?.location, context: context))
        }
    }
}

/// A record as it is written: a map of its fields and its event.
private struct StoredRecord: Encodable {
    let record: EventRecord
    let registration: EventRegistry.Registration

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: RecordEncoding.Key.self)
        try container.encode(record.id, forKey: .id)
        // The seconds `Date` stores, rather than the CBOR package's tag 1 epoch time, whose seconds
        // since 1970 round away the last bit of a date's seconds since 2001.
        try container.encode(record.timestamp.timeIntervalSinceReferenceDate, forKey: .timestamp)
        try container.encode(registration.name, forKey: .name)
        try container.encode(registration.version, forKey: .version)
        try container.encodeIfPresent(record.sourceLocation.map(StoredSourceLocation.init(location:)), forKey: .sourceLocation)
        // The session alone of the context: a vendor destination sends it as the record's device or
        // user identifier, so a record recovered after a relaunch must go out under the one it was
        // first sent with, or the vendor can't drop the second copy (TRAF-122, D4 amended). Any
        // other context value would need a decision of its own on what a record may carry to disk.
        // A record without the key, as releases before TRAF-122 wrote, reads back sessionless.
        try container.encodeIfPresent(record.context[SessionKey.self], forKey: .session)
        try registration.encode(record.event, .event, &container)
    }
}

// This relies on swift-cbor's internals: its decoder holds the value it was handed, so the
// reference stays readable after `init(from:)` returns, and decoding the reference reads nothing.
// That is why the package is pinned exactly (scripts/modules.py); a bump must recheck both, which
// the record round-trip tests in PersistenceTests do.
/// The decoder a value is decoded from, which a record reads in two steps: its name, then its
/// event through the type of that name.
private struct DecoderReference: Decodable {
    let decoder: any Decoder

    init(from decoder: any Decoder) {
        self.decoder = decoder
    }
}

/// A record's call site as it is written: a map, without its file when it equals its file ID, as
/// it does unless `#filePath` was passed.
private struct StoredSourceLocation: Codable {
    let location: SourceLocation

    private enum Key: String, CodingKey {
        case fileID
        case file
        case function
        case line
        case column
    }

    init(location: SourceLocation) {
        self.location = location
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        try container.encode(location.fileID, forKey: .fileID)
        if location.file != location.fileID {
            try container.encode(location.file, forKey: .file)
        }
        try container.encode(location.function, forKey: .function)
        try container.encode(location.line, forKey: .line)
        try container.encode(location.column, forKey: .column)
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        let fileID = try container.decode(String.self, forKey: .fileID)
        location = SourceLocation(
            file: try container.decodeIfPresent(String.self, forKey: .file) ?? fileID,
            fileID: fileID,
            function: try container.decode(String.self, forKey: .function),
            line: try container.decode(Int.self, forKey: .line),
            column: try container.decode(Int.self, forKey: .column)
        )
    }
}
