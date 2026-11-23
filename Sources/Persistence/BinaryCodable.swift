/// A value with a compact binary form, written and read field by field in a fixed order.
///
/// An event type conforms to be kept on disk by a ``SegmentStore`` until it is delivered. Write
/// the conformance in an extension, so the type keeps its memberwise initializer, and encode the
/// stored properties in the same order the initializer decodes them:
///
/// ```swift
/// struct SignedUp: Event {
///     var plan: String
///     var seats: Int
/// }
///
/// extension SignedUp: BinaryCodable {
///     func encode(to encoder: inout BinaryEncoder) {
///         encoder.encode(plan)
///         encoder.encode(seats)
///     }
///
///     init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
///         plan = try decoder.decode()
///         seats = try decoder.decode()
///     }
/// }
/// ```
///
/// The format has no field names or type tags: a value is its fields' bytes, one after another.
/// Integers are little-endian and fixed-width (`Int` and `UInt` as 64 bits on every platform),
/// floating-point numbers their IEEE 754 bits, `Bool` one byte, `String` its UTF-8 count as a
/// `UInt32` and then its bytes, `Array` its count as a `UInt32` and then its elements, and
/// `Optional` a byte, 0 or 1, before the value. Changing a type's fields changes its format, so
/// add a new event type rather than change one that records on disk may still hold.
public protocol BinaryCodable {
    /// Writes this value's fields to `encoder`, in order.
    ///
    /// - Parameter encoder: Where the bytes go.
    func encode(to encoder: inout BinaryEncoder)

    /// Reads a value's fields from `decoder`, in the order ``encode(to:)`` wrote them.
    ///
    /// - Parameter decoder: Where the bytes come from.
    /// - Throws: ``BinaryDecodingError`` when the bytes run out or don't hold a valid value.
    init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError)
}

/// Why bytes couldn't be decoded.
public enum BinaryDecodingError: Error, Sendable, Hashable {
    /// The bytes ended before the value did.
    case endOfData
    /// The bytes don't hold a valid value of the type: a `Bool` byte other than 0 or 1, a string
    /// that isn't UTF-8, or an integer out of the type's range.
    case invalidValue
}
