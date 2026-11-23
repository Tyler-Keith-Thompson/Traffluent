import Events
import Foundation
import Persistence
import Testing

@Suite("BinaryCodable")
struct BinaryCodableTests {
    struct Point: BinaryCodable, Equatable {
        var x: Int32
        var y: Int32

        init(x: Int32, y: Int32) {
            self.x = x
            self.y = y
        }

        func encode(to encoder: inout BinaryEncoder) {
            encoder.encode(x)
            encoder.encode(y)
        }

        init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
            x = try decoder.decode()
            y = try decoder.decode()
        }
    }

    @Test("A store's encoder writes a sensitive value as its value, and its decoder reads it back marked sensitive")
    func sensitive() throws {
        let expectedBytes: [UInt8] = [7, 0, 0, 0, 0, 0, 0, 0]
        var encoder = BinaryEncoder(writingSensitiveValues: true)

        encoder.encode(Sensitive(7))
        var decoder = BinaryDecoder(encoder.bytes[...], readingSensitiveValues: true)
        let actual: Sensitive<Int> = try decoder.decode()

        #expect(encoder.bytes == expectedBytes)
        #expect(actual.value == 7)
        #expect(decoder.isAtEnd)
    }

    @Test("Integers are written little-endian at their fixed width")
    func integerLayout() {
        let expected: [UInt8] = [0x04, 0x03, 0x02, 0x01, 0xFE, 0xFF]
        var sut = BinaryEncoder()

        sut.encode(UInt32(0x0102_0304))
        sut.encode(Int16(-2))

        #expect(sut.bytes == expected)
    }

    @Test("Int and UInt are written as 64 bits")
    func wordLayout() {
        let expected: [UInt8] = [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 7, 0, 0, 0, 0, 0, 0, 0]
        var sut = BinaryEncoder()

        sut.encode(-1)
        sut.encode(UInt(7))

        #expect(sut.bytes == expected)
    }

    @Test("A string is its UTF-8 count as a UInt32, then its UTF-8 bytes")
    func stringLayout() {
        let expected: [UInt8] = [3, 0, 0, 0, 0x68, 0xC3, 0xA9]
        var sut = BinaryEncoder()

        sut.encode("hé")

        #expect(sut.bytes == expected)
    }

    @Test("An array is its count as a UInt32, then its elements; an optional is a byte, 0 or 1, before the value")
    func arrayAndOptionalLayout() {
        let expected: [UInt8] = [2, 0, 0, 0, 1, 9, 0]
        var sut = BinaryEncoder()

        sut.encode([UInt8?.some(9), nil])

        #expect(sut.bytes == expected)
    }

    @Test("A Bool is one byte, 1 or 0")
    func boolLayout() {
        let expected: [UInt8] = [1, 0]
        var sut = BinaryEncoder()

        sut.encode(true)
        sut.encode(false)

        #expect(sut.bytes == expected)
    }

    @Test("A new encoder holds no bytes")
    func emptyEncoder() {
        let sut = BinaryEncoder()

        #expect(sut.bytes.isEmpty)
    }

    @Test("Every standard type reads back as written")
    func roundTrip() throws {
        let expectedDate = Date(timeIntervalSinceReferenceDate: 123_456.789)
        let expectedUUID = UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!
        let expectedDouble = -0.1
        let expectedFloat: Float = 3.5
        let expectedString = "שלום, world"
        let expectedArray = [Point(x: 1, y: -2), Point(x: .max, y: .min)]
        let expectedOptional: String? = nil
        var encoder = BinaryEncoder()
        encoder.encode(UInt8.max)
        encoder.encode(UInt16.max)
        encoder.encode(UInt32.max)
        encoder.encode(UInt64.max)
        encoder.encode(Int8.min)
        encoder.encode(Int16.min)
        encoder.encode(Int32.min)
        encoder.encode(Int64.min)
        encoder.encode(Int.max)
        encoder.encode(UInt.max)
        encoder.encode(true)
        encoder.encode(expectedDouble)
        encoder.encode(expectedFloat)
        encoder.encode(expectedString)
        encoder.encode(expectedArray)
        encoder.encode(expectedOptional)
        encoder.encode(expectedDate)
        encoder.encode(expectedUUID)
        var sut = BinaryDecoder(encoder.bytes)

        #expect(try sut.decode(UInt8.self) == .max)
        #expect(try sut.decode(UInt16.self) == .max)
        #expect(try sut.decode(UInt32.self) == .max)
        #expect(try sut.decode(UInt64.self) == .max)
        #expect(try sut.decode(Int8.self) == .min)
        #expect(try sut.decode(Int16.self) == .min)
        #expect(try sut.decode(Int32.self) == .min)
        #expect(try sut.decode(Int64.self) == .min)
        #expect(try sut.decode(Int.self) == .max)
        #expect(try sut.decode(UInt.self) == .max)
        #expect(try sut.decode(Bool.self) == true)
        #expect(try sut.decode(Double.self) == expectedDouble)
        #expect(try sut.decode(Float.self) == expectedFloat)
        #expect(try sut.decode(String.self) == expectedString)
        #expect(try sut.decode([Point].self) == expectedArray)
        #expect(try sut.decode(String?.self) == expectedOptional)
        #expect(try sut.decode(Date.self) == expectedDate)
        #expect(try sut.decode(UUID.self) == expectedUUID)
        #expect(sut.isAtEnd)
    }

    @Test("Reading past the end throws endOfData")
    func endOfData() {
        let bytes: [UInt8] = [1, 2, 3]
        var sut = BinaryDecoder(bytes)

        #expect(throws: BinaryDecodingError.endOfData) {
            _ = try sut.decode(UInt32.self)
        }
    }

    @Test("A decoder with one byte left is not at its end")
    func oneByteLeft() throws {
        let bytes: [UInt8] = [1, 2]
        var sut = BinaryDecoder(bytes)

        _ = try sut.decode(UInt8.self)

        #expect(!sut.isAtEnd)
    }

    @Test("A UUID from fewer than 16 bytes throws endOfData")
    func shortUUID() {
        let bytes = [UInt8](repeating: 7, count: 15)
        var sut = BinaryDecoder(bytes)

        #expect(throws: BinaryDecodingError.endOfData) {
            _ = try sut.decode(UUID.self)
        }
    }

    @Test("Nothing can be read from no bytes, which are already at their end")
    func emptyDecoder() {
        let bytes: [UInt8] = []
        var sut = BinaryDecoder(bytes)

        #expect(sut.isAtEnd)
        #expect(throws: BinaryDecodingError.endOfData) {
            _ = try sut.decode(UInt8.self)
        }
    }

    @Test("A string whose count runs past the end throws endOfData")
    func stringCountPastEnd() {
        let bytes: [UInt8] = [5, 0, 0, 0, 0x61, 0x62]
        var sut = BinaryDecoder(bytes)

        #expect(throws: BinaryDecodingError.endOfData) {
            _ = try sut.decode(String.self)
        }
    }

    @Test("A string count that is exactly the bytes left reads them all")
    func stringCountAtEnd() throws {
        let bytes: [UInt8] = [2, 0, 0, 0, 0x61, 0x62]
        let expected = "ab"
        var sut = BinaryDecoder(bytes)

        let actual = try sut.decode(String.self)

        #expect(actual == expected)
        #expect(sut.isAtEnd)
    }

    @Test("An array whose count is more than the bytes left throws endOfData before reading elements")
    func arrayCountPastEnd() {
        let bytes: [UInt8] = [0xFF, 0xFF, 0xFF, 0xFF, 1]
        var sut = BinaryDecoder(bytes)

        #expect(throws: BinaryDecodingError.endOfData) {
            _ = try sut.decode([UInt8].self)
        }
    }

    @Test("A string that isn't UTF-8 throws invalidValue")
    func invalidUTF8() {
        let bytes: [UInt8] = [1, 0, 0, 0, 0xFF]
        var sut = BinaryDecoder(bytes)

        #expect(throws: BinaryDecodingError.invalidValue) {
            _ = try sut.decode(String.self)
        }
    }

    @Test("A Bool byte other than 0 or 1 throws invalidValue")
    func invalidBool() {
        let bytes: [UInt8] = [2]
        var sut = BinaryDecoder(bytes)

        #expect(throws: BinaryDecodingError.invalidValue) {
            _ = try sut.decode(Bool.self)
        }
    }

    @Test("An optional's tag other than 0 or 1 throws invalidValue")
    func invalidOptionalTag() {
        let bytes: [UInt8] = [2, 0]
        var sut = BinaryDecoder(bytes)

        #expect(throws: BinaryDecodingError.invalidValue) {
            _ = try sut.decode(UInt8?.self)
        }
    }

    @Test("A decoder over a slice reads from the slice's start")
    func slice() throws {
        let bytes: [UInt8] = [9, 9, 7, 0]
        let expected: UInt16 = 7
        var sut = BinaryDecoder(bytes[2...])

        let actual = try sut.decode(UInt16.self)

        #expect(actual == expected)
        #expect(sut.isAtEnd)
    }
}
