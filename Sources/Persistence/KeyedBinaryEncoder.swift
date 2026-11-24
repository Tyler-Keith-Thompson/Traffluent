/// Writes a map's entries, each a value under its key: what ``BinaryEncoder/encodeMap(_:)`` gives
/// its body.
public struct KeyedBinaryEncoder: Sendable {
    /// The encoder the entries are written to.
    @usableFromInline var encoder: BinaryEncoder
    /// How many entries have been written.
    @usableFromInline var count = 0

    @inlinable
    init(encoder: BinaryEncoder) {
        self.encoder = encoder
    }

    /// Writes `value` under `key`.
    ///
    /// - Parameters:
    ///   - value: The value to write.
    ///   - key: Its key, unique in the map: a property's name.
    @inlinable
    public mutating func encode(_ value: some BinaryCodable, forKey key: StaticString) {
        encoder.writeKey(key)
        encoder.encode(value)
        count += 1
    }

    /// Writes what `body` writes under `key`: one value, such as an event's, written through its
    /// registration.
    package mutating func encode(forKey key: StaticString, _ body: (inout BinaryEncoder) -> Void) {
        encoder.writeKey(key)
        body(&encoder)
        count += 1
    }
}
