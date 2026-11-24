/// Reads values in their ``BinaryCodable`` form, CBOR (RFC 8949), one data item after another,
/// from bytes in memory.
public struct BinaryDecoder: Sendable {
    @usableFromInline let bytes: ArraySlice<UInt8>
    /// Where the next data item starts.
    @usableFromInline var position: Int
    /// Whether a `Sensitive` value can be read; otherwise reading one throws.
    ///
    /// Only a store's decoder reads them, so code outside the library can't recover a sensitive
    /// value from bytes it encoded itself.
    @usableFromInline package let readsSensitiveValues: Bool

    /// A decoder reading `bytes` from their start, which can't read a `Sensitive` value.
    ///
    /// - Parameter bytes: The bytes to read.
    public init(_ bytes: ArraySlice<UInt8>) {
        self.init(bytes, readingSensitiveValues: false)
    }

    /// A decoder reading `bytes` from their start, reading `Sensitive` values when
    /// `readingSensitiveValues` is set: a store's.
    package init(_ bytes: ArraySlice<UInt8>, readingSensitiveValues: Bool) {
        self.bytes = bytes
        position = bytes.startIndex
        readsSensitiveValues = readingSensitiveValues
    }

    /// A decoder reading `bytes` from their start.
    ///
    /// - Parameter bytes: The bytes to read.
    public init(_ bytes: [UInt8]) {
        self.init(bytes[...])
    }

    /// Whether every byte has been read.
    @inlinable
    public var isAtEnd: Bool {
        position == bytes.endIndex
    }

    /// How many bytes are left to read.
    @inlinable
    var remainingCount: Int {
        bytes.endIndex - position
    }

    /// Reads a value of type `type`.
    ///
    /// - Parameter type: The type to read; inferred from the context when left out.
    /// - Returns: The value.
    /// - Throws: ``BinaryDecodingError`` when the bytes run out or don't hold a valid value.
    @inlinable
    public mutating func decode<Value: BinaryCodable>(_ type: Value.Type = Value.self) throws(BinaryDecodingError) -> Value {
        try Value(from: &self)
    }

    /// Reads a map, returning a decoder of its entries by key, and moves past the whole map.
    ///
    /// ```swift
    /// var map = try decoder.decodeMap()
    /// plan = try map.decode(forKey: "plan")
    /// seats = try map.decode(forKey: "seats")
    /// ```
    ///
    /// Entries whose keys are never asked for are skipped: those of properties a later release
    /// removed.
    ///
    /// - Returns: The map's entries.
    /// - Throws: ``BinaryDecodingError/typeMismatch`` when the next value isn't a map, or
    ///   ``BinaryDecodingError`` when its entries run past the end or aren't well formed.
    /// - Complexity: O(*n*), where *n* is the number of bytes the map takes.
    @inlinable
    public mutating func decodeMap() throws(BinaryDecodingError) -> KeyedBinaryDecoder {
        let count = try readCount(of: .map, elementSize: 2)
        let entries = KeyedBinaryDecoder(decoder: self, count: count)
        try skip(itemCount: 2 * count)
        return entries
    }

    /// The next byte, not yet read, or `nil` at the end.
    @inlinable
    package func peek() -> UInt8? {
        position < bytes.endIndex ? bytes[position] : nil
    }

    /// Reads one byte.
    @inlinable
    package mutating func readByte() throws(BinaryDecodingError) -> UInt8 {
        guard position < bytes.endIndex else { throw .endOfData }
        defer { position += 1 }
        return bytes[position]
    }

    /// Reads the next `count` bytes as they are.
    @inlinable
    package mutating func read(_ count: Int) throws(BinaryDecodingError) -> ArraySlice<UInt8> {
        guard count <= remainingCount else { throw .endOfData }
        defer { position += count }
        return bytes[position ..< position + count]
    }

    /// Reads an integer written most significant byte first.
    @inlinable
    package mutating func readBigEndian<Integer: FixedWidthInteger>(_ type: Integer.Type = Integer.self) throws(BinaryDecodingError) -> Integer {
        let size = MemoryLayout<Integer>.size
        guard size <= remainingCount else { throw .endOfData }
        defer { position += size }
        let start = position
        return bytes.withUnsafeBytes { raw in
            Integer(bigEndian: raw.loadUnaligned(fromByteOffset: start - bytes.startIndex, as: Integer.self))
        }
    }

    /// Reads a data item's head: its major type and argument.
    ///
    /// - Throws: ``BinaryDecodingError/endOfData`` when the head runs past the end, or
    ///   ``BinaryDecodingError/invalidValue`` for additional information 28 to 31: reserved, or an
    ///   indefinite length, which this encoding never writes.
    @inlinable
    package mutating func readHead() throws(BinaryDecodingError) -> DataItemHead {
        let initial = try readByte()
        // Three bits always name one of the eight major types.
        let majorType = BinaryMajorType(rawValue: initial >> 5)!
        let information = initial & 0x1F
        let argument: UInt64
        switch information {
        case 0 ..< 24: argument = UInt64(information)
        case 24: argument = UInt64(try readByte())
        // Byte by byte: cheaper than reading a UInt16 through the slice's buffer.
        case 25: argument = UInt64(try readByte()) << 8 | UInt64(try readByte())
        case 26: argument = UInt64(try readBigEndian(UInt32.self))
        case 27: argument = try readBigEndian(UInt64.self)
        default: throw .invalidValue
        }
        return DataItemHead(majorType: majorType, argument: argument)
    }

    /// Reads the head of a data item of type `majorType`, returning its argument.
    ///
    /// - Throws: ``BinaryDecodingError/typeMismatch`` when the item is of another type.
    @inlinable
    mutating func readArgument(of majorType: BinaryMajorType) throws(BinaryDecodingError) -> UInt64 {
        let head = try readHead()
        guard head.majorType == majorType else { throw .typeMismatch }
        return head.argument
    }

    /// Reads the head of a string, an array or a map of type `majorType`, returning its count,
    /// and checks that the bytes left can hold that many elements of at least `elementSize`
    /// bytes each, so a corrupt count can't make a reader allocate more than the input holds.
    @inlinable
    package mutating func readCount(of majorType: BinaryMajorType, elementSize: Int = 1) throws(BinaryDecodingError) -> Int {
        // The argument is read first, then checked against the bytes left after the head:
        // `count(readArgument(...))` would copy the decoder, a retain and a release, to call
        // `count` on it.
        let argument = try readArgument(of: majorType)
        return try Self.count(argument, elementSize: elementSize, bytesLeft: remainingCount)
    }

    /// Moves past the next `itemCount` data items, whatever they hold.
    ///
    /// - Throws: ``BinaryDecodingError`` when an item runs past the end or isn't well formed.
    @inlinable
    mutating func skip(itemCount: Int) throws(BinaryDecodingError) {
        let offset = position - bytes.startIndex
        let end = bytes.withUnsafeBufferPointer { Self.end(ofItems: itemCount, in: $0, from: offset) }
        switch end {
        case .success(let end):
            position = bytes.startIndex + end
        case .failure(let error):
            throw error
        }
    }

    /// Where the `itemCount` data items starting at `offset` in `buffer` end.
    ///
    /// One loop over the raw bytes, rather than `readHead()` per item: every map is skipped once
    /// as it is opened, so this is the decoder's hottest path.
    @inlinable
    static func end(ofItems itemCount: Int, in buffer: UnsafeBufferPointer<UInt8>, from offset: Int) -> Result<Int, BinaryDecodingError> {
        // A count of items still to skip rather than recursion, so nesting as deep as the bytes
        // allow can't overflow the stack. Each item takes a byte at least, so an array or a map
        // may add only as many items as there are bytes left past the ones already pending: the
        // count then stays below the bytes left plus one and can't overflow, even a 32-bit Int.
        var remaining = itemCount
        var cursor = offset
        while remaining > 0 {
            remaining -= 1
            guard cursor < buffer.count else { return .failure(.endOfData) }
            let initial = buffer[cursor]
            cursor += 1
            let information = initial & 0x1F
            var argument = UInt64(information)
            if information >= 24 {
                guard information <= 27 else { return .failure(.invalidValue) }
                let size = 1 << (information - 24)
                guard size <= buffer.count - cursor else { return .failure(.endOfData) }
                argument = 0
                for index in cursor ..< cursor + size {
                    argument = argument << 8 | UInt64(buffer[index])
                }
                cursor += size
            }
            let left = UInt64(buffer.count - cursor)
            // The bytes left once each pending item has its one byte.
            let room = UInt64(max(buffer.count - cursor - remaining, 0))
            switch BinaryMajorType(rawValue: initial >> 5)! {
            case .unsignedInteger, .negativeInteger, .simpleOrFloat:
                break
            case .tag:
                remaining += 1
            case .byteString, .textString:
                guard argument <= left else { return .failure(.endOfData) }
                cursor += Int(argument)
            case .array:
                guard argument <= left else { return .failure(.endOfData) }
                guard argument <= room else { return .failure(.invalidValue) }
                remaining += Int(argument)
            case .map:
                guard argument <= left / 2 else { return .failure(.endOfData) }
                guard argument <= room / 2 else { return .failure(.invalidValue) }
                remaining += 2 * Int(argument)
            }
        }
        return .success(cursor)
    }

    /// Reads a text string and compares it with `key`, moving past it either way.
    ///
    /// - Returns: Whether the next item is the text string `key`.
    @inlinable
    mutating func readKey(matching key: StaticString) throws(BinaryDecodingError) -> Bool {
        let offset = position - bytes.startIndex
        let outcome = key.withUTF8Buffer { utf8 in
            bytes.withUnsafeBufferPointer { Self.readKey(utf8, in: $0, from: offset) }
        }
        switch outcome {
        case .matched(let end):
            position = bytes.startIndex + end
            return true
        case .different(let end):
            position = bytes.startIndex + end
            return false
        case .notText:
            // A key of another type, which this encoding never writes: no match, and skipped.
            try skip(itemCount: 1)
            return false
        case .failed(let error):
            throw error
        }
    }

    /// Reads the text string at `offset` in `buffer` and compares it with `key`, in one pass
    /// over the raw bytes: every property read reads its key.
    @inlinable
    static func readKey(_ key: UnsafeBufferPointer<UInt8>, in buffer: UnsafeBufferPointer<UInt8>, from offset: Int) -> KeyOutcome {
        guard offset < buffer.count else { return .failed(.endOfData) }
        let initial = buffer[offset]
        guard initial >> 5 == BinaryMajorType.textString.rawValue else { return .notText }
        var cursor = offset + 1
        let information = initial & 0x1F
        var count = Int(information)
        if information >= 24 {
            guard information <= 27 else { return .failed(.invalidValue) }
            let size = 1 << (information - 24)
            guard size <= buffer.count - cursor else { return .failed(.endOfData) }
            var argument: UInt64 = 0
            for index in cursor ..< cursor + size {
                argument = argument << 8 | UInt64(buffer[index])
            }
            cursor += size
            guard argument <= UInt64(buffer.count - cursor) else { return .failed(.endOfData) }
            count = Int(argument)
        }
        guard count <= buffer.count - cursor else { return .failed(.endOfData) }
        let end = cursor + count
        guard key.count == count else { return .different(end: end) }
        for index in 0 ..< count where key[index] != buffer[cursor + index] {
            return .different(end: end)
        }
        return .matched(end: end)
    }

    /// `argument` as the count of a string's bytes, an array's elements or a map's entries,
    /// checked against the bytes left, each element taking at least `elementSize` of them: a
    /// corrupt count can't make a reader allocate, or skip, more than the input holds.
    @inlinable
    package func count(_ argument: UInt64, elementSize: Int) throws(BinaryDecodingError) -> Int {
        try Self.count(argument, elementSize: elementSize, bytesLeft: remainingCount)
    }

    /// `argument` as a count of elements of at least `elementSize` bytes each, checked against
    /// `bytesLeft`.
    @inlinable
    static func count(_ argument: UInt64, elementSize: Int, bytesLeft: Int) throws(BinaryDecodingError) -> Int {
        // `Int(exactly:)`: on a 32-bit platform a count past `Int.max` can't be a valid count.
        guard let count = Int(exactly: argument), count <= bytesLeft / elementSize else { throw .endOfData }
        return count
    }
}
