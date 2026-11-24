/// Writes values in their ``BinaryCodable`` form, CBOR (RFC 8949), one data item per value.
public struct BinaryEncoder: Sendable {
    /// The bytes written so far.
    public var bytes: [UInt8] {
        buffer
    }

    /// The bytes written so far, which the encoding appends to.
    @usableFromInline var buffer: [UInt8]
    /// Whether a `Sensitive` value is written as its value; otherwise it is written as CBOR's
    /// `undefined`.
    ///
    /// Only a store's encoder writes them, so code outside the library can't turn a sensitive
    /// value into bytes by encoding it, or the event holding it, itself.
    @usableFromInline package let writesSensitiveValues: Bool

    /// An encoder with nothing written, which writes `undefined` for a `Sensitive` value.
    public init() {
        self.init(writingSensitiveValues: false)
    }

    /// An encoder with nothing written, writing `Sensitive` values as their values when
    /// `writingSensitiveValues` is set: a store's.
    @usableFromInline
    package init(writingSensitiveValues: Bool) {
        buffer = []
        writesSensitiveValues = writingSensitiveValues
    }

    /// A store's encoder whose bytes start with `prefix`, written by the caller: a segment
    /// frame's, which may hold a record.
    init(prefix: [UInt8]) {
        buffer = prefix
        writesSensitiveValues = true
    }

    /// Writes `value`.
    ///
    /// - Parameter value: The value to write.
    @inlinable
    public mutating func encode(_ value: some BinaryCodable) {
        value.encode(to: &self)
    }

    /// Writes a map, one entry for each value `body` encodes with its key.
    ///
    /// ```swift
    /// encoder.encodeMap { map in
    ///     map.encode(plan, forKey: "plan")
    ///     map.encode(seats, forKey: "seats")
    /// }
    /// ```
    ///
    /// - Parameter body: Encodes the map's entries, in the order they are written.
    /// - Complexity: O(1) besides `body`'s work, or O(*n*) in the bytes written when the map has 24
    ///   entries or more, whose count takes more room than was set aside for it.
    @inlinable
    public mutating func encodeMap(_ body: (inout KeyedBinaryEncoder) -> Void) {
        let start = buffer.count
        // A one-byte head is set aside and filled in once the entries are counted, so the map is
        // written in one pass with its count up front (CBOR's definite length), as RFC 8949's
        // preferred serialization asks.
        buffer.append(BinaryMajorType.map.initialByte)
        var map = KeyedBinaryEncoder(encoder: BinaryEncoder(writingSensitiveValues: writesSensitiveValues))
        // Swapped rather than copied, so the bytes have one owner and appending never copies them.
        swap(&self, &map.encoder)
        body(&map)
        swap(&self, &map.encoder)
        if map.count < 24 {
            buffer[start] |= UInt8(map.count)
        } else {
            widenMapHead(at: start, count: map.count)
        }
    }

    /// Replaces the one-byte map head at `start` with the longer one `count` entries need.
    @usableFromInline @inline(never)
    mutating func widenMapHead(at start: Int, count: Int) {
        var head = BinaryEncoder(writingSensitiveValues: false)
        head.writeHead(.map, UInt64(count))
        buffer.replaceSubrange(start ..< start + 1, with: head.buffer)
    }

    /// Writes a data item's head: its major type and `argument`, in the fewest bytes that hold it.
    @inlinable
    mutating func writeHead(_ majorType: BinaryMajorType, _ argument: UInt64) {
        let initial = majorType.initialByte
        switch argument {
        case 0 ..< 24:
            buffer.append(initial | UInt8(argument))
        case 24 ... 0xFF:
            buffer.append(initial | 24)
            buffer.append(UInt8(argument))
        case 0x100 ... 0xFFFF:
            buffer.append(initial | 25)
            buffer.append(UInt8(truncatingIfNeeded: argument >> 8))
            buffer.append(UInt8(truncatingIfNeeded: argument))
        case 0x1_0000 ... 0xFFFF_FFFF:
            buffer.append(initial | 26)
            writeBigEndian(UInt32(argument))
        default:
            buffer.append(initial | 27)
            writeBigEndian(argument)
        }
    }

    /// Writes `count` as the head of a string or an array of that many bytes or elements.
    @inlinable
    mutating func writeHead(_ majorType: BinaryMajorType, count: Int) {
        // A count is never negative, and an Int always fits in a UInt64.
        writeHead(majorType, UInt64(count))
    }

    /// Inserts `byte` at `offset`, before the bytes written since.
    ///
    /// - Complexity: O(*n*), where *n* is the number of bytes after `offset`.
    @usableFromInline @inline(never)
    mutating func insert(_ byte: UInt8, at offset: Int) {
        buffer.insert(byte, at: offset)
    }

    /// Writes one byte as it is.
    @inlinable
    mutating func write(_ byte: UInt8) {
        buffer.append(byte)
    }

    /// Writes `value`'s bytes, most significant first, as CBOR's arguments and floats are.
    @inlinable
    mutating func writeBigEndian<Integer: FixedWidthInteger>(_ value: Integer) {
        Swift.withUnsafeBytes(of: value.bigEndian) { buffer.append(contentsOf: $0) }
    }

    /// Writes `value`'s bytes, least significant first: a segment frame's fields, which aren't
    /// CBOR.
    mutating func writeLittleEndian<Integer: FixedWidthInteger>(_ value: Integer) {
        Swift.withUnsafeBytes(of: value.littleEndian) { buffer.append(contentsOf: $0) }
    }

    /// Writes `bytes` as they are.
    @inlinable
    mutating func write(contentsOf newBytes: some Collection<UInt8>) {
        buffer.append(contentsOf: newBytes)
    }

    /// Writes `key` as a text string.
    @inlinable
    mutating func writeKey(_ key: StaticString) {
        key.withUTF8Buffer { utf8 in
            writeHead(.textString, count: utf8.count)
            for byte in utf8 {
                buffer.append(byte)
            }
        }
    }

    /// Overwrites the bytes at `offset` with `value`, least significant first.
    mutating func overwriteLittleEndian(_ value: UInt32, at offset: Int) {
        Swift.withUnsafeBytes(of: value.littleEndian) { source in
            buffer.withUnsafeMutableBytes { target in
                target.baseAddress!.advanced(by: offset).copyMemory(from: source.baseAddress!, byteCount: 4)
            }
        }
    }
}
