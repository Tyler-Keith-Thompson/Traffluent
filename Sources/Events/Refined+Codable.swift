extension Refined: Encodable where Value: Encodable {
    /// Writes the value, as its own conformance writes it.
    ///
    /// - Parameter encoder: Where the value goes.
    /// - Throws: What encoding the value throws.
    public func encode(to encoder: any Encoder) throws {
        // The encoder itself, so the bytes are the value's own, as if it weren't refined.
        try value.encode(to: encoder)
    }
}

extension Refined: Decodable where Value: Decodable {
    /// Reads a value, refined again by `Rule`.
    ///
    /// - Parameter decoder: Where the value comes from.
    /// - Throws: `DecodingError.dataCorrupted` when the value no longer satisfies `Rule` (a later
    ///   release tightened it), or what decoding the value throws.
    public init(from decoder: any Decoder) throws {
        // A decoding error rather than the initializer's UnsatisfiedConstraint: the bytes come
        // from disk, which a release with another rule may have written, and a store reports a
        // record it can't decode rather than deliver a value that breaks its type's rule.
        let value = try Value(from: decoder)
        guard let refined = try? Refined(value) else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "The value no longer satisfies its refinement."
            ))
        }
        self = refined
    }
}
