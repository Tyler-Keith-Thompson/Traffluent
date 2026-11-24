// CBOR written and read by hand, for the subset the standard types need (definite lengths,
// integer and float heads, text and byte strings, arrays, maps, tag 37), rather than through a
// package. Rejected: SwiftCBOR (valpackett), whose decoder builds an indirect enum tree with an
// allocation per item and a dictionary per map, and whose typed path is Codable; PotentCodables'
// PotentCBOR and CBORCoding (SomeRandomiOSDev), both Codable encoders, which D7 rules out for speed.
// A generated conformance here writes straight into a byte array and reads each key in place.
// SwiftCBOR stays as the tests' independent decoder. A package becomes the right choice if one
// offers a non-Codable streaming writer and reader as fast as this, on Linux too.

/// A value with a compact binary form, CBOR (RFC 8949), that a store keeps on disk.
///
/// An event type conforms to be kept on disk by a ``SegmentStore`` until it is delivered. Write
/// the conformance in an extension, so the type keeps its memberwise initializer, and encode the
/// stored properties as a map, each under its name:
///
/// ```swift
/// struct SignedUp: Event {
///     var plan: String
///     var seats: Int
///     var coupon: String?
/// }
///
/// extension SignedUp: BinaryCodable {
///     func encode(to encoder: inout BinaryEncoder) {
///         encoder.encodeMap { map in
///             map.encode(plan, forKey: "plan")
///             map.encode(seats, forKey: "seats")
///             map.encode(coupon, forKey: "coupon")
///         }
///     }
///
///     init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
///         var map = try decoder.decodeMap()
///         plan = try map.decode(forKey: "plan")
///         seats = try map.decode(forKey: "seats")
///         coupon = try map.decode(forKey: "coupon")
///     }
/// }
/// ```
///
/// `@Event` (module `EventMacros`) writes this conformance for you.
///
/// Because each property is found by its name, an event type can change while records written
/// before the change are still on disk. A property removed since leaves an entry the decoder
/// skips, an optional property added since reads as `nil`, and properties can be reordered. A
/// change the older bytes can't satisfy, such as a required property added or a property's type
/// changed, makes ``init(from:)`` throw, and the store drops the record and reports it.
///
/// Each value is one CBOR data item, so any CBOR decoder can read the bytes. Integers are CBOR
/// integers in the fewest bytes that hold them, `Bool` is `true` or `false`, `Double` and `Float`
/// are double- and single-precision floats, `String` a text string, `Array` an array, `Optional`
/// `null` or the value (in a one-element array when the value's own bytes start with `null`, as
/// a nested optional's `nil` does, or with that array's head), `Date`
/// a double of its seconds since 2001-01-01 UTC, and `UUID` a 16-byte byte string tagged 37. An
/// encoder of your own writes a `Sensitive` value as `undefined`.
public protocol BinaryCodable {
    /// Writes this value to `encoder` as one data item: a map of the properties, for a type of
    /// your own.
    ///
    /// - Parameter encoder: Where the bytes go.
    func encode(to encoder: inout BinaryEncoder)

    /// Reads a value ``encode(to:)`` wrote from `decoder`.
    ///
    /// - Parameter decoder: Where the bytes come from.
    /// - Throws: ``BinaryDecodingError`` when the bytes run out or don't hold a valid value.
    init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError)
}

/// Why bytes couldn't be decoded.
public enum BinaryDecodingError: Error, Sendable, Hashable {
    /// The bytes ended before the value did.
    case endOfData
    /// The bytes hold a value of another kind than the type reads: a string where an integer
    /// was expected, say, after a property's type changed.
    case typeMismatch
    /// A map has no entry for a key a non-optional value is read from: a required property added
    /// since the map was written.
    case keyNotFound
    /// The bytes don't hold a valid value of the type: a string that isn't UTF-8, an integer out
    /// of the type's range, a value that no longer satisfies its refinement, or a head CBOR
    /// reserves or this encoding never writes.
    case invalidValue
}
