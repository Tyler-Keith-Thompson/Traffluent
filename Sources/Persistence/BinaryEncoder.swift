/// Writes values in their ``BinaryCodable`` form, one after another.
public struct BinaryEncoder: Sendable {
    /// The bytes written so far.
    public private(set) var bytes: [UInt8]

    /// An encoder with nothing written.
    public init() {
        bytes = []
    }

    /// An encoder whose bytes start with `prefix`, written by the caller.
    init(prefix: [UInt8]) {
        bytes = prefix
    }

    /// Writes `value`.
    ///
    /// - Parameter value: The value to write.
    public mutating func encode(_ value: some BinaryCodable) {
        value.encode(to: &self)
    }

    /// Writes `value`'s bytes, least significant first.
    mutating func writeLittleEndian<Integer: FixedWidthInteger>(_ value: Integer) {
        withUnsafeBytes(of: value.littleEndian) { bytes.append(contentsOf: $0) }
    }

    /// Writes `count` as the `UInt32` that precedes a string's or an array's contents.
    ///
    /// - Precondition: `count` fits in a `UInt32`.
    mutating func writeCount(_ count: Int) {
        // A trap rather than an error: encoding can't fail, and a string or array of four
        // billion elements in one analytics event is a programming mistake.
        guard let count = UInt32(exactly: count) else {
            preconditionFailure("Binary encoding holds at most \(UInt32.max) elements, not \(count)")
        }
        writeLittleEndian(count)
    }

    /// Writes `bytes` as they are.
    mutating func write(contentsOf newBytes: some Collection<UInt8>) {
        bytes.append(contentsOf: newBytes)
    }

    /// Overwrites the bytes at `offset` with `value`, least significant first.
    mutating func overwriteLittleEndian(_ value: UInt32, at offset: Int) {
        withUnsafeBytes(of: value.littleEndian) { source in
            bytes.withUnsafeMutableBytes { target in
                target.baseAddress!.advanced(by: offset).copyMemory(from: source.baseAddress!, byteCount: 4)
            }
        }
    }
}
