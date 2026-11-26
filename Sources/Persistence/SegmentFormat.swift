internal import Checksums
import Events
import SystemPackage

/// The bytes of a segment file.
///
/// A segment starts with an 8-byte header: the magic number `TRFL` (`54 52 46 4C`), the format
/// version as a little-endian `UInt16` (2), and two reserved zero bytes. Frames follow, each a
/// little-endian `UInt32` payload length, the payload's CRC-32 as a little-endian `UInt32`, and the
/// payload. A payload's first byte is its kind:
///
/// - 0, a record: its bytes in ``RecordEncoding``, a CBOR map. Records are numbered from 0 in the
///   order they appear.
/// - 1, a delivery mark: the numbers, as little-endian `UInt32`s, of records in this segment a
///   delivery was about to hand to destinations.
///
/// A segment whose header names a later version is one a newer release of the app wrote, read
/// back after a rollback: it is left alone for that release to read again. One whose header names
/// an earlier version holds records in a form this release can't read: recovery deletes it and
/// reports its bytes as a corruption.
enum SegmentFormat {
    /// The header every segment of this version starts with.
    static let header: [UInt8] = [0x54, 0x52, 0x46, 0x4C, 2, 0, 0, 0]
    /// The format version `header` names.
    static let version: UInt16 = 2
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

    /// A frame's bytes, at the start of a buffer that may hold more past them.
    struct Frame {
        /// The frame's bytes, then whatever the buffer held past them.
        let buffer: [UInt8]
        /// How many bytes of `buffer` the frame takes.
        let byteCount: Int

        /// Writes the frame's bytes to `descriptor`.
        func write(to descriptor: FileDescriptor) throws(Errno) {
            try buffer.withUnsafeBytes { bytes in
                Result { () throws(Errno) in try descriptor.writeAll(UnsafeRawBufferPointer(rebasing: bytes[..<byteCount])) }
            }.get()
        }
    }

    /// The frame of `record`, whose event `registration` encodes, written over `buffer`: one
    /// kept from an earlier frame, so a record's frame needs no allocation of its own; `nil` when
    /// its payload is over `UInt32.max` bytes, which a frame's length can't state.
    static func recordFrame(of record: EventRecord, registration: EventRegistry.Registration, reusing buffer: consuming [UInt8]) -> Frame? {
        var encoder = frameEncoder(of: .record, reusing: buffer)
        RecordEncoding.encode(record, registration: registration, to: &encoder)
        guard seal(&encoder) else { return nil }
        return Frame(buffer: encoder.buffer, byteCount: encoder.byteCount)
    }

    /// The frame of a delivery mark naming records `indices`; `nil` when its payload is over
    /// `UInt32.max` bytes, which a frame's length can't state.
    static func deliveryMarkFrame(of indices: [UInt32]) -> [UInt8]? {
        var encoder = frameEncoder(of: .deliveryMark, reusing: [])
        for index in indices {
            encoder.writeLittleEndian(index)
        }
        guard seal(&encoder) else { return nil }
        return encoder.takeBytes()
    }

    /// A segment holding only the record frames `frames` of the segment `bytes`, renumbered from
    /// 0 in their order, then a delivery mark naming `marked`, their new numbers, when it isn't
    /// empty.
    ///
    /// Each frame's bytes are copied as they are, so its checksum still holds. `nil` when the
    /// delivery mark would be larger than a frame can be.
    ///
    /// - Complexity: O(*n*), where *n* is the number of bytes the frames take.
    static func compacted(_ bytes: [UInt8], keeping frames: [RecordFrame], marking marked: [UInt32]) -> [UInt8]? {
        var compacted = header
        for frame in frames {
            // The payload range starts after the kind byte, which follows the frame's header.
            compacted += bytes[frame.payload.lowerBound - 1 - frameHeaderByteCount..<frame.payload.upperBound]
        }
        if !marked.isEmpty {
            guard let mark = deliveryMarkFrame(of: marked) else { return nil }
            compacted += mark
        }
        return compacted
    }

    /// An encoder writing over `buffer`, holding room for a frame's length and checksum, then
    /// `kind`'s byte.
    private static func frameEncoder(of kind: Kind, reusing buffer: consuming [UInt8]) -> BinaryEncoder {
        var encoder = BinaryEncoder(reusing: buffer)
        encoder.writeLittleEndian(UInt64(0))
        encoder.write(kind.rawValue)
        return encoder
    }

    /// Fills in the length and checksum of the frame `encoder` holds.
    ///
    /// - Returns: Whether it could: `false`, leaving them unset, for a payload over `UInt32.max`
    ///   bytes (a single event of 4 GiB), whose length a frame can't state.
    private static func seal(_ encoder: inout BinaryEncoder) -> Bool {
        encoder.withWrittenBytes { frame in
            guard let length = UInt32(exactly: frame.count - frameHeaderByteCount) else { return false }
            let checksum = CRC32.checksum(of: UnsafeRawBufferPointer(rebasing: frame[frameHeaderByteCount...]))
            frame.storeBytes(of: length.littleEndian, toByteOffset: 0, as: UInt32.self)
            frame.storeBytes(of: checksum.littleEndian, toByteOffset: 4, as: UInt32.self)
            return true
        }
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
