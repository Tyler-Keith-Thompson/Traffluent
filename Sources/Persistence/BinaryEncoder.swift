/// Writes values in their ``BinaryCodable`` form, CBOR (RFC 8949), one data item per value.
public struct BinaryEncoder: Sendable {
    /// The bytes written so far.
    ///
    /// - Complexity: O(*n*), where *n* is the number of bytes written.
    public var bytes: [UInt8] {
        byteCount == storage.count ? storage : Array(storage[..<byteCount])
    }

    /// The bytes written, then room for the next writes: zeros, or an earlier frame's bytes in a
    /// buffer a store's encoder writes over.
    ///
    /// Room is kept rather than appended to, so each write reserves its bytes and copies them in
    /// with one check that the storage is uniquely referenced, and a value's head and its bytes
    /// are one write; appending to an array checks once per append. The room doubles when it
    /// runs out.
    @usableFromInline var storage: [UInt8]
    /// How many bytes of `storage` are written.
    @usableFromInline var byteCount: Int
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
        storage = []
        byteCount = 0
        writesSensitiveValues = writingSensitiveValues
    }

    /// A store's encoder with nothing written, writing over `storage`'s bytes: a segment
    /// frame's, in a buffer kept from an earlier frame.
    init(reusing storage: consuming [UInt8]) {
        self.storage = storage
        byteCount = 0
        writesSensitiveValues = true
    }

    /// The buffer the bytes are written to: the bytes written, then room for more.
    var buffer: [UInt8] {
        storage
    }

    /// Calls `body` with the bytes written, which it may change.
    mutating func withWrittenBytes<Value>(_ body: (UnsafeMutableRawBufferPointer) -> Value) -> Value {
        let count = byteCount
        return storage.withUnsafeMutableBytes { body(UnsafeMutableRawBufferPointer(rebasing: $0[..<count])) }
    }

    /// The bytes written, leaving the encoder empty, so the caller holds the only reference to
    /// them and can change them in place.
    mutating func takeBytes() -> [UInt8] {
        var bytes: [UInt8] = []
        swap(&bytes, &storage)
        bytes.removeLast(bytes.count - byteCount)
        byteCount = 0
        return bytes
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
        let start = byteCount
        // A one-byte head is set aside and filled in once the entries are counted, so the map is
        // written in one pass with its count up front (CBOR's definite length), as RFC 8949's
        // preferred serialization asks.
        write(BinaryMajorType.map.initialByte)
        var map = KeyedBinaryEncoder(encoder: BinaryEncoder(writingSensitiveValues: writesSensitiveValues))
        // Swapped rather than copied, so the bytes have one owner and appending never copies them.
        swap(&self, &map.encoder)
        body(&map)
        swap(&self, &map.encoder)
        if map.count < 24 {
            storage[start] |= UInt8(map.count)
        } else {
            widenMapHead(at: start, count: map.count)
        }
    }

    /// Replaces the one-byte map head at `start` with the longer one `count` entries need.
    @usableFromInline @inline(never)
    mutating func widenMapHead(at start: Int, count: Int) {
        var head = BinaryEncoder(writingSensitiveValues: false)
        head.writeHead(.map, UInt64(count))
        storage.replaceSubrange(start ..< start + 1, with: head.bytes)
        byteCount += head.byteCount - 1
    }

    /// Writes a data item's head: its major type and `argument`, in the fewest bytes that hold it.
    @inlinable
    mutating func writeHead(_ majorType: BinaryMajorType, _ argument: UInt64) {
        let initial = majorType.initialByte
        switch argument {
        case 0 ..< 24:
            write(initial | UInt8(argument))
        case 24 ... 0xFF:
            write(byteCount: 2) { target in
                target.storeBytes(of: initial | 24, as: UInt8.self)
                target.storeBytes(of: UInt8(argument), toByteOffset: 1, as: UInt8.self)
            }
        case 0x100 ... 0xFFFF:
            writeHead(initialByte: initial | 25, bigEndian: UInt16(argument))
        case 0x1_0000 ... 0xFFFF_FFFF:
            writeHead(initialByte: initial | 26, bigEndian: UInt32(argument))
        default:
            writeHead(initialByte: initial | 27, bigEndian: argument)
        }
    }

    /// Writes `initial`, then `argument` most significant byte first.
    @inlinable
    mutating func writeHead<Argument: FixedWidthInteger>(initialByte initial: UInt8, bigEndian argument: Argument) {
        write(byteCount: 1 + MemoryLayout<Argument>.size) { target in
            target.storeBytes(of: initial, as: UInt8.self)
            target.storeBytes(of: argument.bigEndian, toByteOffset: 1, as: Argument.self)
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
        storage.insert(byte, at: offset)
        byteCount += 1
    }

    /// Writes one byte as it is.
    @inlinable
    mutating func write(_ byte: UInt8) {
        write(byteCount: 1) { $0.storeBytes(of: byte, as: UInt8.self) }
    }

    /// Writes `value`'s bytes, most significant first, as CBOR's arguments and floats are.
    @inlinable
    mutating func writeBigEndian<Integer: FixedWidthInteger>(_ value: Integer) {
        write(byteCount: MemoryLayout<Integer>.size) { $0.storeBytes(of: value.bigEndian, as: Integer.self) }
    }

    /// Writes `value`'s bytes, least significant first: a segment frame's fields, which aren't
    /// CBOR.
    mutating func writeLittleEndian<Integer: FixedWidthInteger>(_ value: Integer) {
        write(byteCount: MemoryLayout<Integer>.size) { $0.storeBytes(of: value.littleEndian, as: Integer.self) }
    }

    /// Writes `bytes` as they are.
    @inlinable
    mutating func write(contentsOf bytes: UnsafeRawBufferPointer) {
        guard let source = bytes.baseAddress, !bytes.isEmpty else { return }
        write(byteCount: bytes.count) { $0.copyMemory(from: source, byteCount: bytes.count) }
    }

    /// Writes `utf8` as a text string: its head and its bytes in one write.
    @inlinable
    mutating func writeText(_ utf8: UnsafeBufferPointer<UInt8>) {
        guard utf8.count < 24, let source = utf8.baseAddress else {
            writeHead(.textString, count: utf8.count)
            write(contentsOf: UnsafeRawBufferPointer(utf8))
            return
        }
        write(byteCount: 1 + utf8.count) { target in
            target.storeBytes(of: BinaryMajorType.textString.initialByte | UInt8(utf8.count), as: UInt8.self)
            (target + 1).copyMemory(from: source, byteCount: utf8.count)
        }
    }

    /// Writes `key` as a text string.
    @inlinable
    mutating func writeKey(_ key: StaticString) {
        key.withUTF8Buffer { writeText($0) }
    }

    /// Writes `count` bytes after those written so far, which `body` initializes from the
    /// address it is given.
    ///
    /// - Precondition: `count` is positive.
    @inlinable
    mutating func write(byteCount count: Int, _ body: (UnsafeMutableRawPointer) -> Void) {
        if storage.count - byteCount < count {
            makeRoom(for: count)
        }
        let start = byteCount
        // Not empty: the room just made holds `count` bytes, and `count` is positive.
        storage.withUnsafeMutableBytes { body($0.baseAddress.unsafelyUnwrapped + start) }
        byteCount += count
    }

    /// Grows `storage` to hold `count` more bytes than are written, at least doubling it, so
    /// writing *n* bytes grows it O(log *n*) times.
    @usableFromInline @inline(never)
    mutating func makeRoom(for count: Int) {
        let grown = max(byteCount + count, storage.count * 2, 64)
        let written = byteCount
        storage = storage.withUnsafeBytes { old in
            [UInt8](unsafeUninitializedCapacity: grown) { new, initializedCount in
                // The bytes written are kept, and the room past them is zeros.
                let base = UnsafeMutableRawPointer(new.baseAddress.unsafelyUnwrapped)
                if written > 0 {
                    base.copyMemory(from: old.baseAddress.unsafelyUnwrapped, byteCount: written)
                }
                (base + written).initializeMemory(as: UInt8.self, repeating: 0, count: grown - written)
                initializedCount = grown
            }
        }
    }
}
