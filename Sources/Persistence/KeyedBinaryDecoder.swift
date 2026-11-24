/// Reads a map's entries by key: what ``BinaryDecoder/decodeMap()`` returns.
///
/// Keys are found in any order. Reading them in the order they were written, as a type's
/// `init(from:)` does when its properties haven't changed, finds each at once; a key out of place
/// is looked for among all the entries.
public struct KeyedBinaryDecoder: Sendable {
    /// The map's bytes, positioned at the key of entry `nextIndex`.
    @usableFromInline var decoder: BinaryDecoder
    /// Where the first entry's key starts.
    @usableFromInline let start: Int
    /// How many entries the map has.
    @usableFromInline let count: Int
    /// The entry `decoder` is positioned at; `count` once past the last.
    @usableFromInline var nextIndex = 0

    @inlinable
    init(decoder: BinaryDecoder, count: Int) {
        self.decoder = decoder
        start = decoder.position
        self.count = count
    }

    /// Reads the value under `key`.
    ///
    /// - Parameters:
    ///   - type: The type to read; inferred from the context when left out.
    ///   - key: The value's key: a property's name.
    /// - Returns: The value.
    /// - Throws: ``BinaryDecodingError/keyNotFound`` when the map has no entry for `key`, or
    ///   what reading the value throws.
    /// - Complexity: O(1) besides reading the value when `key` is the entry after the last one
    ///   read; otherwise O(*n*), where *n* is the number of bytes the map takes.
    @inlinable
    public mutating func decode<Value: BinaryCodable>(_ type: Value.Type = Value.self, forKey key: StaticString) throws(BinaryDecodingError) -> Value {
        guard try find(key) else { throw .keyNotFound }
        return try decodeValue()
    }

    /// Reads the optional value under `key`, `nil` when the map has no entry for it: a property
    /// added since the map was written.
    ///
    /// - Parameters:
    ///   - type: The type to read; inferred from the context when left out.
    ///   - key: The value's key: a property's name.
    /// - Returns: The value, or `nil` when the entry is missing or holds `null`.
    /// - Throws: What reading the value throws.
    /// - Complexity: O(1) besides reading the value when `key` is the entry after the last one
    ///   read; otherwise O(*n*), where *n* is the number of bytes the map takes.
    @inlinable
    public mutating func decode<Wrapped: BinaryCodable>(_ type: Wrapped?.Type = Wrapped?.self, forKey key: StaticString) throws(BinaryDecodingError) -> Wrapped? {
        guard try find(key) else { return nil }
        return try decodeValue()
    }

    /// A decoder positioned at the value under `key`, or `nil` when the map has no entry for
    /// it: for a value read through its registration, such as a record's event.
    package mutating func decoder(forKey key: StaticString) throws(BinaryDecodingError) -> BinaryDecoder? {
        guard try find(key) else { return nil }
        let value = decoder
        try decoder.skip(itemCount: 1)
        nextIndex += 1
        return value
    }

    /// Reads the value of the entry `decoder` is positioned at, past its key.
    @inlinable
    mutating func decodeValue<Value: BinaryCodable>() throws(BinaryDecodingError) -> Value {
        let value: Value = try decoder.decode()
        nextIndex += 1
        return value
    }

    /// Positions `decoder` at the value under `key`, past its key, returning whether there is
    /// one; when there isn't, `decoder` stays where it was.
    @inlinable
    mutating func find(_ key: StaticString) throws(BinaryDecodingError) -> Bool {
        let position = decoder.position
        if nextIndex < count, try decoder.readKey(matching: key) {
            return true
        }
        decoder.position = position
        return try search(key)
    }

    /// Looks for `key` among all the entries, for a key out of place: a property added, removed
    /// or moved since the map was written.
    @usableFromInline @inline(never)
    mutating func search(_ key: StaticString) throws(BinaryDecodingError) -> Bool {
        let position = decoder.position
        decoder.position = start
        for index in 0 ..< count {
            if try decoder.readKey(matching: key) {
                nextIndex = index
                return true
            }
            try decoder.skip(itemCount: 1)
        }
        decoder.position = position
        return false
    }
}
