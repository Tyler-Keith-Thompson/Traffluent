public import Foundation

extension BinaryCodable where Self: FixedWidthInteger {
    /// Writes the integer's bytes, least significant first.
    public func encode(to encoder: inout BinaryEncoder) {
        encoder.writeLittleEndian(self)
    }

    /// Reads an integer written least significant byte first.
    public init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
        self = try decoder.readLittleEndian()
    }
}

extension UInt8: BinaryCodable {}
extension UInt16: BinaryCodable {}
extension UInt32: BinaryCodable {}
extension UInt64: BinaryCodable {}
extension Int8: BinaryCodable {}
extension Int16: BinaryCodable {}
extension Int32: BinaryCodable {}
extension Int64: BinaryCodable {}

extension Int: BinaryCodable {
    /// Writes the integer as an `Int64`, so its bytes are the same on 32- and 64-bit platforms.
    public func encode(to encoder: inout BinaryEncoder) {
        encoder.writeLittleEndian(Int64(self))
    }

    /// Reads an integer written as an `Int64`.
    ///
    /// - Throws: ``BinaryDecodingError/invalidValue`` when it doesn't fit this platform's `Int`.
    public init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
        guard let value = Int(exactly: try decoder.readLittleEndian(Int64.self)) else { throw .invalidValue }
        self = value
    }
}

extension UInt: BinaryCodable {
    /// Writes the integer as a `UInt64`, so its bytes are the same on 32- and 64-bit platforms.
    public func encode(to encoder: inout BinaryEncoder) {
        encoder.writeLittleEndian(UInt64(self))
    }

    /// Reads an integer written as a `UInt64`.
    ///
    /// - Throws: ``BinaryDecodingError/invalidValue`` when it doesn't fit this platform's `UInt`.
    public init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
        guard let value = UInt(exactly: try decoder.readLittleEndian(UInt64.self)) else { throw .invalidValue }
        self = value
    }
}

extension Bool: BinaryCodable {
    /// Writes one byte: 1 for `true`, 0 for `false`.
    public func encode(to encoder: inout BinaryEncoder) {
        encoder.writeLittleEndian(UInt8(self ? 1 : 0))
    }

    /// Reads one byte, 0 or 1.
    ///
    /// - Throws: ``BinaryDecodingError/invalidValue`` for any other byte.
    public init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
        switch try decoder.readLittleEndian(UInt8.self) {
        case 0: self = false
        case 1: self = true
        default: throw .invalidValue
        }
    }
}

extension Double: BinaryCodable {
    /// Writes the number's IEEE 754 bits, least significant first.
    public func encode(to encoder: inout BinaryEncoder) {
        encoder.writeLittleEndian(bitPattern)
    }

    /// Reads a number's IEEE 754 bits.
    public init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
        self = Double(bitPattern: try decoder.readLittleEndian())
    }
}

extension Float: BinaryCodable {
    /// Writes the number's IEEE 754 bits, least significant first.
    public func encode(to encoder: inout BinaryEncoder) {
        encoder.writeLittleEndian(bitPattern)
    }

    /// Reads a number's IEEE 754 bits.
    public init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
        self = Float(bitPattern: try decoder.readLittleEndian())
    }
}

extension String: BinaryCodable {
    /// Writes the string's UTF-8 byte count as a `UInt32`, then its UTF-8 bytes.
    ///
    /// - Precondition: The string has at most `UInt32.max` UTF-8 bytes.
    public func encode(to encoder: inout BinaryEncoder) {
        var string = self
        string.withUTF8 { utf8 in
            encoder.writeCount(utf8.count)
            encoder.write(contentsOf: utf8)
        }
    }

    /// Reads a string written as its UTF-8 byte count and bytes.
    ///
    /// - Throws: ``BinaryDecodingError/invalidValue`` when the bytes aren't valid UTF-8.
    public init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
        let utf8 = try decoder.read(decoder.readCount())
        guard let string = String(validating: utf8, as: UTF8.self) else { throw .invalidValue }
        self = string
    }
}

extension Array: BinaryCodable where Element: BinaryCodable {
    /// Writes the element count as a `UInt32`, then each element in order.
    ///
    /// - Precondition: The array has at most `UInt32.max` elements.
    public func encode(to encoder: inout BinaryEncoder) {
        encoder.writeCount(count)
        for element in self {
            encoder.encode(element)
        }
    }

    /// Reads an array written as its count and elements.
    public init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
        let count = try decoder.readCount()
        var elements: [Element] = []
        elements.reserveCapacity(count)
        for _ in 0..<count {
            elements.append(try decoder.decode())
        }
        self = elements
    }
}

extension Optional: BinaryCodable where Wrapped: BinaryCodable {
    /// Writes a byte, 0 for `nil` or 1, then the value if there is one.
    public func encode(to encoder: inout BinaryEncoder) {
        switch self {
        case .none:
            encoder.writeLittleEndian(UInt8(0))
        case .some(let value):
            encoder.writeLittleEndian(UInt8(1))
            encoder.encode(value)
        }
    }

    /// Reads an optional written as a byte, 0 or 1, and the value if there is one.
    ///
    /// - Throws: ``BinaryDecodingError/invalidValue`` when the byte is neither 0 nor 1.
    public init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
        switch try decoder.readLittleEndian(UInt8.self) {
        case 0: self = .none
        case 1: self = .some(try decoder.decode())
        default: throw .invalidValue
        }
    }
}

extension Date: BinaryCodable {
    /// Writes the date's seconds since the reference date (2001-01-01, UTC) as a `Double`, the
    /// value `Date` stores, so it reads back exactly.
    public func encode(to encoder: inout BinaryEncoder) {
        encoder.encode(timeIntervalSinceReferenceDate)
    }

    /// Reads a date written as its seconds since the reference date.
    public init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
        self = Date(timeIntervalSinceReferenceDate: try decoder.decode())
    }
}

extension UUID: BinaryCodable {
    /// Writes the UUID's 16 bytes in order.
    public func encode(to encoder: inout BinaryEncoder) {
        withUnsafeBytes(of: uuid) { encoder.write(contentsOf: $0) }
    }

    /// Reads a UUID's 16 bytes.
    public init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
        let bytes = try decoder.read(16)
        var uuid: uuid_t = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        withUnsafeMutableBytes(of: &uuid) { target in
            target.copyBytes(from: bytes)
        }
        self = UUID(uuid: uuid)
    }
}
