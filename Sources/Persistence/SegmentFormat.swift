internal import Checksums
import Events
import Foundation

/// The bytes of a segment file.
///
/// A segment starts with an 8-byte header: the magic number `TRFL` (`54 52 46 4C`), the format
/// version as a little-endian `UInt16` (1), and two reserved zero bytes. Frames follow, each a
/// little-endian `UInt32` payload length, the payload's CRC-32 as a little-endian `UInt32`, and the
/// payload. A payload's first byte is its kind:
///
/// - 0, a record: its timestamp, `fileID`, `file` (`nil` when it equals `fileID`), function, line,
///   column and event name, then the event's own ``BinaryCodable`` bytes, all in the binary
///   encoding. Records are numbered from 0 in the order they appear.
/// - 1, a delivery mark: the numbers, as little-endian `UInt32`s, of records in this segment a
///   delivery was about to hand to destinations.
///
/// A segment whose header names a later version is one a newer release of the app wrote, read
/// back after a rollback: it is left alone for that release to read again.
enum SegmentFormat {
    /// The header every segment of this version starts with.
    static let header: [UInt8] = [0x54, 0x52, 0x46, 0x4C, 1, 0, 0, 0]
    /// The format version `header` names.
    static let version: UInt16 = 1
    /// The bytes before each frame's payload: its length and checksum.
    static let frameHeaderByteCount = 8

    /// What a frame's payload holds.
    enum Kind: UInt8 {
        case record = 0
        case deliveryMark = 1
    }

    /// A record's frame in a segment: its number and where its payload, after the kind byte, lies.
    struct RecordFrame: Hashable {
        let index: UInt32
        let payload: Range<Int>
    }

    /// What a segment's bytes hold, up to the first frame that isn't intact.
    struct Contents {
        /// How many bytes from the start are a header and intact frames.
        var validByteCount: Int
        /// The record frames, in order.
        var records: [RecordFrame]
        /// The numbers of records a delivery mark names.
        var marked: Set<UInt32>
    }

    /// What a segment's bytes are.
    enum Reading {
        /// The header is missing, isn't this format's, or names an earlier version this one can't
        /// read: none of the bytes can be read.
        case unreadable
        /// The header names a later version of the format, `version`.
        case newerVersion(UInt16)
        /// A segment of this format, read up to its first torn or corrupt frame.
        case segment(Contents)
    }

    /// Reads `bytes` as a segment, stopping at the first frame that is torn (its length runs past
    /// the end), corrupt (its checksum fails), empty, of an unknown kind, or a malformed mark.
    ///
    /// - Complexity: O(*n*), where *n* is the number of bytes.
    static func read(_ bytes: [UInt8]) -> Reading {
        guard bytes.count >= header.count, bytes[0..<4].elementsEqual(header[0..<4]) else { return .unreadable }
        let version = UInt16(bytes[4]) | UInt16(bytes[5]) << 8
        // A later version may give the reserved bytes a meaning, so only this one requires zeros.
        guard version <= Self.version else { return .newerVersion(version) }
        guard bytes[4..<header.count].elementsEqual(header[4...]) else { return .unreadable }
        var contents = Contents(validByteCount: header.count, records: [], marked: [])
        var offset = header.count
        reading: while bytes.count - offset >= frameHeaderByteCount {
            let checksum = bytes.littleEndianUInt32(at: offset + 4)
            let start = offset + frameHeaderByteCount
            // `Int(exactly:)`: on a 32-bit platform a length past `Int.max` is torn anyway.
            guard let length = Int(exactly: bytes.littleEndianUInt32(at: offset)), length >= 1, length <= bytes.count - start else { break }
            let payload = start..<start + length
            guard bytes.crc32(of: payload) == checksum else { break }
            switch Kind(rawValue: bytes[start]) {
            case .record:
                // A segment rolls before its count reaches UInt32.max, so a frame past that is
                // not one this format wrote.
                guard let index = UInt32(exactly: contents.records.count), index < UInt32.max else { break reading }
                contents.records.append(RecordFrame(index: index, payload: start + 1..<payload.upperBound))
            case .deliveryMark:
                guard (length - 1) % 4 == 0 else { break reading }
                for numberOffset in stride(from: start + 1, to: payload.upperBound, by: 4) {
                    contents.marked.insert(bytes.littleEndianUInt32(at: numberOffset))
                }
            case nil:
                break reading
            }
            offset = payload.upperBound
            contents.validByteCount = offset
        }
        return .segment(contents)
    }

    /// The frame of `record`, whose event `registration` encodes.
    static func recordFrame(of record: EventRecord, registration: EventRegistry.Registration) -> [UInt8] {
        var encoder = frameEncoder(of: .record)
        let location = record.sourceLocation
        encoder.encode(record.timestamp)
        encoder.encode(location.fileID)
        encoder.encode(location.file == location.fileID ? nil : location.file)
        encoder.encode(location.function)
        encoder.encode(location.line)
        encoder.encode(location.column)
        encoder.encode(registration.name)
        registration.encode(record.event, &encoder)
        return sealed(encoder)
    }

    /// The frame of a delivery mark naming records `indices`.
    static func deliveryMarkFrame(of indices: [UInt32]) -> [UInt8] {
        var encoder = frameEncoder(of: .deliveryMark)
        for index in indices {
            encoder.encode(index)
        }
        return sealed(encoder)
    }

    /// The record whose payload (after the kind byte) is `payload`, decoded through `registry`:
    /// a record with no tag, tracked in the top-level context.
    ///
    /// - Throws: ``BinaryDecodingError`` when the payload isn't a record of a registered event
    ///   type, or holds bytes past the event's.
    static func record(from payload: ArraySlice<UInt8>, registry: EventRegistry) throws(BinaryDecodingError) -> EventRecord {
        var decoder = BinaryDecoder(payload)
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
        let location = SourceLocation(file: file ?? fileID, fileID: fileID, function: function, line: line, column: column)
        return EventRecord(event: event, timestamp: timestamp, sourceLocation: location)
    }

    /// An encoder holding room for a frame's length and checksum, then `kind`'s byte.
    private static func frameEncoder(of kind: Kind) -> BinaryEncoder {
        BinaryEncoder(prefix: [0, 0, 0, 0, 0, 0, 0, 0, kind.rawValue])
    }

    /// The frame `encoder` holds, with its length and checksum filled in.
    private static func sealed(_ encoder: BinaryEncoder) -> [UInt8] {
        var encoder = encoder
        let payload = frameHeaderByteCount..<encoder.bytes.count
        // A payload over UInt32.max bytes would need a single event of 4 GiB.
        guard let length = UInt32(exactly: payload.count) else {
            preconditionFailure("A record's frame holds at most \(UInt32.max) bytes, not \(payload.count)")
        }
        let checksum = encoder.bytes.crc32(of: payload)
        encoder.overwriteLittleEndian(length, at: 0)
        encoder.overwriteLittleEndian(checksum, at: 4)
        return encoder.bytes
    }
}

extension [UInt8] {
    /// The little-endian `UInt32` at `offset`.
    fileprivate func littleEndianUInt32(at offset: Int) -> UInt32 {
        withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self)) }
    }

    /// The CRC-32 of the bytes in `range`.
    fileprivate func crc32(of range: Range<Int>) -> UInt32 {
        withUnsafeBytes { CRC32.checksum(of: UnsafeRawBufferPointer(rebasing: $0[range])) }
    }
}
