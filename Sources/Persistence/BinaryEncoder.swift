/// Writes values in their ``BinaryCodable`` form, one after another.
public struct BinaryEncoder: Sendable {
    /// The bytes written so far.
    public private(set) var bytes: [UInt8]
    /// Whether a `Sensitive` value is written as its value; otherwise it writes nothing.
    ///
    /// Only a store's encoder writes them, so code outside the library can't turn a sensitive
    /// value into bytes by encoding it, or the event holding it, itself.
    package let writesSensitiveValues: Bool

    /// An encoder with nothing written, which writes nothing for a `Sensitive` value.
    public init() {
        self.init(writingSensitiveValues: false)
    }

    /// An encoder with nothing written, writing `Sensitive` values as their values when
    /// `writingSensitiveValues` is set: a store's.
    package init(writingSensitiveValues: Bool) {
        bytes = []
        writesSensitiveValues = writingSensitiveValues
    }

    /// A store's encoder whose bytes start with `prefix`, written by the caller: a segment
    /// frame's, which may hold a record.
    init(prefix: [UInt8]) {
        bytes = prefix
        writesSensitiveValues = true
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
