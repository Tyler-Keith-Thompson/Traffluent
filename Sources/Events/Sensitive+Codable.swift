extension Sensitive: Encodable where Value: Encodable {
    /// Writes the value as it is for a store, so the store can deliver it to a destination that
    /// reveals it; writes `nil` (CBOR's and JSON's `null`) for any other encoder.
    ///
    /// The bytes on disk hold the value in the clear, as every other property's do: the store is
    /// the app's own, in its own container. Encoding an event yourself writes `nil` in its place,
    /// so a redacted record's event can't be turned back into the value.
    ///
    /// - Parameter encoder: Where the value goes.
    /// - Throws: What encoding the value throws.
    public func encode(to encoder: any Encoder) throws {
        guard SensitiveCoding.revealsValues else {
            var container = encoder.singleValueContainer()
            try container.encodeNil()
            return
        }
        // The encoder itself rather than a single-value container's `encode(_:)`, so the value is
        // written by its own conformance, as it would be in Sensitive's place: a Date as the
        // seconds `Date` stores, not as a container's special case of it.
        try value.encode(to: encoder)
    }
}

extension Sensitive: Decodable where Value: Decodable {
    /// Reads a value a store wrote, marked sensitive again.
    ///
    /// - Parameter decoder: Where the value comes from.
    /// - Throws: `DecodingError.dataCorrupted` for any decoder but a store's, which can't read
    ///   sensitive values, or what decoding the value throws.
    public init(from decoder: any Decoder) throws {
        guard SensitiveCoding.revealsValues else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Only a store reads a sensitive value."
            ))
        }
        self.init(try Value(from: decoder))
    }
}
