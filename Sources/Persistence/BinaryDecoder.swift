/// Reads values in their ``BinaryCodable`` form, one after another, from bytes in memory.
public struct BinaryDecoder: Sendable {
    private let bytes: ArraySlice<UInt8>
    private var position: Int
    /// Whether a `Sensitive` value can be read; otherwise reading one throws.
    ///
    /// Only a store's decoder reads them, so code outside the library can't recover a sensitive
    /// value from bytes it encoded itself.
    package let readsSensitiveValues: Bool

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
    public var isAtEnd: Bool {
        position == bytes.endIndex
    }

    /// How many bytes are left to read.
    var remainingCount: Int {
        bytes.endIndex - position
    }

    /// Reads a value of type `type`.
    ///
    /// - Parameter type: The type to read; inferred from the context when left out.
    /// - Returns: The value.
    /// - Throws: ``BinaryDecodingError`` when the bytes run out or don't hold a valid value.
    public mutating func decode<Value: BinaryCodable>(_ type: Value.Type = Value.self) throws(BinaryDecodingError) -> Value {
        try Value(from: &self)
    }

    /// Reads the next `count` bytes as they are.
    mutating func read(_ count: Int) throws(BinaryDecodingError) -> ArraySlice<UInt8> {
        guard count <= remainingCount else { throw .endOfData }
        defer { position += count }
        return bytes[position..<position + count]
    }

    /// Every byte not yet read.
    mutating func readRest() -> ArraySlice<UInt8> {
        defer { position = bytes.endIndex }
        return bytes[position...]
    }

    /// Reads an integer written least significant byte first.
    mutating func readLittleEndian<Integer: FixedWidthInteger>(_ type: Integer.Type = Integer.self) throws(BinaryDecodingError) -> Integer {
        let size = MemoryLayout<Integer>.size
        guard size <= remainingCount else { throw .endOfData }
        defer { position += size }
        let start = position
        return bytes.withUnsafeBytes { raw in
            Integer(littleEndian: raw.loadUnaligned(fromByteOffset: start - bytes.startIndex, as: Integer.self))
        }
    }

    /// Reads the `UInt32` count that precedes a string's or an array's contents, checking that
    /// at least that many bytes are left, so a corrupt count can't make a reader allocate more
    /// than the input holds.
    mutating func readCount() throws(BinaryDecodingError) -> Int {
        // `Int(exactly:)`: on a 32-bit platform a count past `Int.max` can't be a valid count.
        guard let count = Int(exactly: try readLittleEndian(UInt32.self)) else { throw .endOfData }
        guard count <= remainingCount else { throw .endOfData }
        return count
    }
}
