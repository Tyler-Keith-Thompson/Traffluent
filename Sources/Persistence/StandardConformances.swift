public import Events
public import Foundation

extension BinaryCodable where Self: FixedWidthInteger {
    /// Writes the integer as a CBOR integer in the fewest bytes that hold it: an unsigned
    /// integer (major type 0), or for a negative one, a negative integer (major type 1).
    @inlinable
    public func encode(to encoder: inout BinaryEncoder) {
        if self < 0 {
            // CBOR writes a negative n as -1 - n, which is ~n in two's complement and fits.
            encoder.writeHead(.negativeInteger, UInt64(truncatingIfNeeded: ~self))
        } else {
            encoder.writeHead(.unsignedInteger, UInt64(truncatingIfNeeded: self))
        }
    }

    /// Reads a CBOR integer.
    ///
    /// - Throws: ``BinaryDecodingError/typeMismatch`` when the value isn't an integer, or
    ///   ``BinaryDecodingError/invalidValue`` when it doesn't fit this type.
    @inlinable
    public init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
        let head = try decoder.readHead()
        switch head.majorType {
        case .unsignedInteger:
            guard let value = Self(exactly: head.argument) else { throw .invalidValue }
            self = value
        case .negativeInteger:
            // -1 - n is ~n: a type that holds n holds it, if it is signed.
            guard Self.isSigned, let magnitude = Self(exactly: head.argument) else { throw .invalidValue }
            self = ~magnitude
        default:
            throw .typeMismatch
        }
    }
}

extension UInt8: BinaryCodable {}
extension UInt16: BinaryCodable {}
extension UInt32: BinaryCodable {}
extension UInt64: BinaryCodable {}
extension UInt: BinaryCodable {}
extension Int8: BinaryCodable {}
extension Int16: BinaryCodable {}
extension Int32: BinaryCodable {}
extension Int64: BinaryCodable {}
extension Int: BinaryCodable {}

extension Bool: BinaryCodable {
    /// Writes CBOR's `true` or `false`.
    @inlinable
    public func encode(to encoder: inout BinaryEncoder) {
        encoder.write(self ? BinarySimpleValue.true : BinarySimpleValue.false)
    }

    /// Reads CBOR's `true` or `false`.
    ///
    /// - Throws: ``BinaryDecodingError/typeMismatch`` for any other value.
    @inlinable
    public init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
        switch try decoder.readByte() {
        case BinarySimpleValue.false: self = false
        case BinarySimpleValue.true: self = true
        default: throw .typeMismatch
        }
    }
}

extension Double: BinaryCodable {
    /// Writes the number as a CBOR double-precision float: its IEEE 754 bits, most significant
    /// first.
    @inlinable
    public func encode(to encoder: inout BinaryEncoder) {
        encoder.write(BinarySimpleValue.float64)
        encoder.writeBigEndian(bitPattern)
    }

    /// Reads a CBOR double- or single-precision float.
    ///
    /// - Throws: ``BinaryDecodingError/typeMismatch`` when the value isn't one.
    @inlinable
    public init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
        switch try decoder.readByte() {
        case BinarySimpleValue.float64: self = Double(bitPattern: try decoder.readBigEndian())
        case BinarySimpleValue.float32: self = Double(Float(bitPattern: try decoder.readBigEndian()))
        default: throw .typeMismatch
        }
    }
}

extension Float: BinaryCodable {
    /// Writes the number as a CBOR single-precision float: its IEEE 754 bits, most significant
    /// first.
    @inlinable
    public func encode(to encoder: inout BinaryEncoder) {
        encoder.write(BinarySimpleValue.float32)
        encoder.writeBigEndian(bitPattern)
    }

    /// Reads a CBOR single-precision float.
    ///
    /// - Throws: ``BinaryDecodingError/typeMismatch`` when the value isn't one.
    @inlinable
    public init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
        guard try decoder.readByte() == BinarySimpleValue.float32 else { throw .typeMismatch }
        self = Float(bitPattern: try decoder.readBigEndian())
    }
}

extension String: BinaryCodable {
    /// Writes the string as a CBOR text string: its UTF-8 byte count, then its UTF-8 bytes.
    @inlinable
    public func encode(to encoder: inout BinaryEncoder) {
        // Read in place when the string is contiguous UTF-8, as a native one is: `withUTF8` is
        // mutating, so it would copy the string, a retain and a release per string written.
        let written: Void? = utf8.withContiguousStorageIfAvailable { encoder.writeText($0) }
        if written == nil {
            var string = self
            string.withUTF8 { encoder.writeText($0) }
        }
    }

    /// Reads a CBOR text string.
    ///
    /// - Throws: ``BinaryDecodingError/typeMismatch`` when the value isn't a text string, or
    ///   ``BinaryDecodingError/invalidValue`` when its bytes aren't valid UTF-8.
    @inlinable
    public init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
        let utf8 = try decoder.read(decoder.readCount(of: .textString))
        guard let string = utf8.withUnsafeBufferPointer(String.init(validatingUTF8Bytes:)) else { throw .invalidValue }
        self = string
    }
}

extension String {
    /// The string `utf8` holds, or `nil` when it isn't valid UTF-8.
    @inlinable
    init?(validatingUTF8Bytes utf8: UnsafeBufferPointer<UInt8>) {
        // ASCII, which keys and most values are, is valid UTF-8 as it is, so decoding it repairs
        // nothing; `String(validating:as:)` is generic over its input, and unspecialized it
        // costs several times as much, in type metadata lookups, as the string's bytes do.
        if utf8.allSatisfy({ $0 < 0x80 }) {
            self = String(decoding: utf8, as: UTF8.self)
        } else {
            guard let string = String(validating: utf8, as: UTF8.self) else { return nil }
            self = string
        }
    }
}

extension Array: BinaryCodable where Element: BinaryCodable {
    /// Writes the array as a CBOR array: its element count, then each element in order.
    @inlinable
    public func encode(to encoder: inout BinaryEncoder) {
        encoder.writeHead(.array, count: count)
        for element in self {
            encoder.encode(element)
        }
    }

    /// Reads a CBOR array.
    ///
    /// - Throws: ``BinaryDecodingError/typeMismatch`` when the value isn't an array, or what
    ///   reading an element throws.
    @inlinable
    public init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
        let count = try decoder.readCount(of: .array)
        var elements: [Element] = []
        elements.reserveCapacity(count)
        for _ in 0 ..< count {
            elements.append(try decoder.decode())
        }
        self = elements
    }
}

extension Optional: BinaryCodable where Wrapped: BinaryCodable {
    /// The head of a one-element array, which a value is wrapped in when its own bytes could be
    /// mistaken for `nil`'s or for this wrapper's.
    @usableFromInline package static var wrapperHead: UInt8 {
        BinaryMajorType.array.initialByte | 1
    }

    /// Writes CBOR's `null` for `nil`, or the value: as it is, or as the one element of an array
    /// when its bytes start with `null` or with that array's head, so `.some(nil)` reads back as
    /// itself even through a type that writes the optional it wraps, like `Sensitive<Int?>`.
    @inlinable
    public func encode(to encoder: inout BinaryEncoder) {
        switch self {
        case .none:
            encoder.write(BinarySimpleValue.null)
        case .some(let value):
            // Checked on the bytes written rather than on the type, which can't see an optional
            // that a wrapper such as Sensitive or Refined forwards to.
            let start = encoder.byteCount
            encoder.encode(value)
            if start < encoder.byteCount,
               encoder.storage[start] == BinarySimpleValue.null || encoder.storage[start] == Self.wrapperHead {
                encoder.insert(Self.wrapperHead, at: start)
            }
        }
    }

    /// Reads `nil` from CBOR's `null`, or the value, unwrapped from the one-element array
    /// ``encode(to:)`` may have put it in.
    ///
    /// - Throws: What reading the value throws.
    @inlinable
    public init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
        switch decoder.peek() {
        case BinarySimpleValue.null:
            _ = try decoder.readByte()
            self = .none
        case Self.wrapperHead:
            _ = try decoder.readByte()
            self = .some(try decoder.decode())
        default:
            self = .some(try decoder.decode())
        }
    }
}

extension Date: BinaryCodable {
    /// Writes the date as a CBOR double-precision float of its seconds since the reference date
    /// (2001-01-01, UTC), the value `Date` stores, so it reads back exactly.
    @inlinable
    public func encode(to encoder: inout BinaryEncoder) {
        encoder.encode(timeIntervalSinceReferenceDate)
    }

    /// Reads a date written as its seconds since the reference date.
    ///
    /// - Throws: ``BinaryDecodingError/typeMismatch`` when the value isn't a float.
    @inlinable
    public init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
        self = Date(timeIntervalSinceReferenceDate: try decoder.decode())
    }
}

extension UUID: BinaryCodable {
    /// Writes the UUID as a CBOR byte string of its 16 bytes in order, tagged 37 (UUID, in IANA's
    /// CBOR tags registry).
    @inlinable
    public func encode(to encoder: inout BinaryEncoder) {
        encoder.writeHead(.tag, UUID.cborTag)
        encoder.writeHead(.byteString, 16)
        Swift.withUnsafeBytes(of: uuid) { encoder.write(contentsOf: $0) }
    }

    /// Reads a UUID written as a byte string of 16 bytes, tagged 37.
    ///
    /// - Throws: ``BinaryDecodingError/typeMismatch`` when the value isn't a tagged byte string,
    ///   or ``BinaryDecodingError/invalidValue`` when it has another tag or length.
    @inlinable
    public init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
        guard try decoder.readArgument(of: .tag) == UUID.cborTag, try decoder.readArgument(of: .byteString) == 16 else { throw .invalidValue }
        let bytes = try decoder.read(16)
        var uuid: uuid_t = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        withUnsafeMutableBytes(of: &uuid) { target in
            target.copyBytes(from: bytes)
        }
        self = UUID(uuid: uuid)
    }

    /// CBOR's tag for a UUID (RFC 9562's binary form).
    @usableFromInline package static let cborTag: UInt64 = 37
}

extension Sensitive: BinaryCodable where Value: BinaryCodable {
    /// Writes the value as it is to a store's encoder, so the store can deliver it to a
    /// destination that reveals it; writes CBOR's `undefined` to an encoder of your own,
    /// ``BinaryEncoder/init()``'s.
    ///
    /// The bytes on disk hold the value in the clear, as every other property's do: the store is
    /// the app's own, in its own container. An encoder of your own writes `undefined` in its
    /// place, so encoding a redacted record's event can't recover the value.
    // Not inlinable: the value is package to the library, so only its own code reads it.
    public func encode(to encoder: inout BinaryEncoder) {
        guard encoder.writesSensitiveValues else {
            encoder.write(BinarySimpleValue.undefined)
            return
        }
        encoder.encode(value)
    }

    /// Reads a value a store's encoder wrote, marked sensitive again.
    ///
    /// - Throws: ``BinaryDecodingError/invalidValue`` from a decoder of your own, which can't
    ///   read sensitive values, or what reading the value throws.
    @inlinable
    public init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
        guard decoder.readsSensitiveValues else { throw .invalidValue }
        self.init(try decoder.decode(Value.self))
    }
}

extension Refined: BinaryCodable where Value: BinaryCodable {
    /// Writes the value.
    @inlinable
    public func encode(to encoder: inout BinaryEncoder) {
        encoder.encode(value)
    }

    /// Reads a value, refined again by `Rule`.
    ///
    /// - Throws: ``BinaryDecodingError/invalidValue`` when the value no longer satisfies `Rule`
    ///   (a later release tightened it), or what reading the value throws.
    @inlinable
    public init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
        // A decoding error rather than the initializer's UnsatisfiedConstraint: the bytes come
        // from disk, which a release with another rule may have written, and a store reports a
        // record it can't decode rather than deliver a value that breaks its type's rule.
        let value = try decoder.decode(Value.self)
        guard let refined = try? Refined(value) else { throw .invalidValue }
        self = refined
    }
}
