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
            encoder.encodeMap { map in
                map.encode(x, forKey: "x")
                map.encode(y, forKey: "y")
            }
        }

        init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
            var map = try decoder.decodeMap()
            x = try map.decode(forKey: "x")
            y = try map.decode(forKey: "y")
        }
    }

    @Test("A store's encoder writes a sensitive value as its value, and its decoder reads it back marked sensitive")
    func sensitive() throws {
        let expectedBytes: [UInt8] = [0x07]
        var encoder = BinaryEncoder(writingSensitiveValues: true)

        encoder.encode(Sensitive(7))
        var decoder = BinaryDecoder(encoder.bytes[...], readingSensitiveValues: true)
        let actual: Sensitive<Int> = try decoder.decode()

        #expect(encoder.bytes == expectedBytes)
        #expect(actual.value == 7)
        #expect(decoder.isAtEnd)
    }

    // RFC 8949, Appendix A, for every value it lists that a standard type here writes.

    @Test("Unsigned integers are CBOR unsigned integers in the fewest bytes, as RFC 8949's examples show")
    func unsignedIntegerVectors() {
        let cases: [(value: UInt64, expected: [UInt8])] = [
            (0, [0x00]), (1, [0x01]), (10, [0x0A]), (23, [0x17]), (24, [0x18, 0x18]), (25, [0x18, 0x19]),
            (100, [0x18, 0x64]), (255, [0x18, 0xFF]), (256, [0x19, 0x01, 0x00]), (1000, [0x19, 0x03, 0xE8]),
            (65535, [0x19, 0xFF, 0xFF]), (65536, [0x1A, 0x00, 0x01, 0x00, 0x00]), (1_000_000, [0x1A, 0x00, 0x0F, 0x42, 0x40]),
            (4_294_967_295, [0x1A, 0xFF, 0xFF, 0xFF, 0xFF]), (4_294_967_296, [0x1B, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00]),
            (1_000_000_000_000, [0x1B, 0x00, 0x00, 0x00, 0xE8, 0xD4, 0xA5, 0x10, 0x00]),
            (18_446_744_073_709_551_615, [0x1B, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]),
        ]
        for (value, expected) in cases {
            var sut = BinaryEncoder()

            sut.encode(value)

            #expect(sut.bytes == expected, "\(value)")
        }
    }

    @Test("Negative integers are CBOR negative integers, -1 - n, as RFC 8949's examples show; every width writes a value the same")
    func negativeIntegerVectors() {
        let cases: [(value: Int64, expected: [UInt8])] = [
            (-1, [0x20]), (-10, [0x29]), (-24, [0x37]), (-25, [0x38, 0x18]), (-100, [0x38, 0x63]), (-1000, [0x39, 0x03, 0xE7]),
            (.min, [0x3B, 0x7F, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]),
        ]
        for (value, expected) in cases {
            var sut = BinaryEncoder()

            sut.encode(value)

            #expect(sut.bytes == expected, "\(value)")
        }
        let expectedSmall: [UInt8] = [0x38, 0x63, 0x38, 0x63, 0x38, 0x63, 0x38, 0x63]
        var sut = BinaryEncoder()

        sut.encode(Int8(-100))
        sut.encode(Int16(-100))
        sut.encode(Int32(-100))
        sut.encode(-100)

        #expect(sut.bytes == expectedSmall)
    }

    @Test("Doubles and Floats are CBOR double- and single-precision floats, most significant byte first")
    func floatVectors() {
        let expected: [UInt8] = [0xFB, 0x3F, 0xF1, 0x99, 0x99, 0x99, 0x99, 0x99, 0x9A, 0xFA, 0x47, 0xC3, 0x50, 0x00]
        var sut = BinaryEncoder()

        sut.encode(1.1)
        sut.encode(Float(100_000.0))

        #expect(sut.bytes == expected)
    }

    @Test("Bools are CBOR's true and false; nil is null")
    func simpleValueVectors() {
        let expected: [UInt8] = [0xF5, 0xF4, 0xF6]
        var sut = BinaryEncoder()

        sut.encode(true)
        sut.encode(false)
        sut.encode(Int?.none)

        #expect(sut.bytes == expected)
    }

    @Test("Strings are CBOR text strings, their UTF-8 count then their UTF-8 bytes, as RFC 8949's examples show")
    func stringVectors() {
        let cases: [(value: String, expected: [UInt8])] = [
            ("", [0x60]), ("a", [0x61, 0x61]), ("IETF", [0x64, 0x49, 0x45, 0x54, 0x46]), ("\"\\", [0x62, 0x22, 0x5C]),
            ("\u{00FC}", [0x62, 0xC3, 0xBC]), ("\u{6C34}", [0x63, 0xE6, 0xB0, 0xB4]),
            (String(repeating: "x", count: 24), [0x78, 0x18] + Array(repeating: 0x78, count: 24)),
        ]
        for (value, expected) in cases {
            var sut = BinaryEncoder()

            sut.encode(value)

            #expect(sut.bytes == expected, "\(value)")
        }
    }

    @Test("Arrays are CBOR arrays, their count then their elements, as RFC 8949's examples show")
    func arrayVectors() {
        let empty: [Int] = []
        let expectedLong: [UInt8] = [0x98, 0x19] + (1 ... 23).map { UInt8($0) } + [0x18, 0x18, 0x18, 0x19]
        let expected: [UInt8] = [0x80, 0x83, 0x01, 0x02, 0x03] + expectedLong
        var sut = BinaryEncoder()

        sut.encode(empty)
        sut.encode([1, 2, 3])
        sut.encode(Array(1 ... 25))

        #expect(sut.bytes == expected)
    }

    @Test("A map is a CBOR map, its count then each key and value, as RFC 8949's {\"a\": 1, \"b\": [2, 3]} shows")
    func mapVector() {
        let expected: [UInt8] = [0xA2, 0x61, 0x61, 0x01, 0x61, 0x62, 0x82, 0x02, 0x03]
        var sut = BinaryEncoder()

        sut.encodeMap { map in
            map.encode(1, forKey: "a")
            map.encode([2, 3], forKey: "b")
        }

        #expect(sut.bytes == expected)
    }

    @Test("An empty map is one byte, 0xA0")
    func emptyMapVector() {
        let expected: [UInt8] = [0xA0]
        var sut = BinaryEncoder()

        sut.encodeMap { _ in }

        #expect(sut.bytes == expected)
    }

    @Test("A map of 23 entries keeps its one-byte head; one of 24 and one of 256 take the longer heads, entries unchanged")
    func mapCountBoundaries() throws {
        func map(of count: Int) -> [UInt8] {
            var encoder = BinaryEncoder()
            encoder.encodeMap { map in
                for value in 0 ..< count {
                    map.encode(value, forKey: "k")
                }
            }
            return encoder.bytes
        }
        func entries(_ count: Int) -> [UInt8] {
            (0 ..< count).flatMap { value -> [UInt8] in
                var encoder = BinaryEncoder()
                encoder.encode(value)
                return [0x61, 0x6B] + encoder.bytes
            }
        }
        let expected23 = [0xB7] + entries(23)
        let expected24 = [0xB8, 0x18] + entries(24)
        let expected256 = [0xB9, 0x01, 0x00] + entries(256)

        let actual23 = map(of: 23)
        let actual24 = map(of: 24)
        let actual256 = map(of: 256)

        #expect(actual23 == expected23)
        #expect(actual24 == expected24)
        #expect(actual256 == expected256)
    }

    @Test("A UUID is a 16-byte CBOR byte string tagged 37; a Date is a double of its seconds since 2001")
    func uuidAndDateVectors() {
        let uuid = UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!
        let expected: [UInt8] = [0xD8, 0x25, 0x50, 0xE6, 0x21, 0xE1, 0xF8, 0xC3, 0x6C, 0x49, 0x5A, 0x93, 0xFC, 0x0C, 0x24, 0x7A, 0x3E, 0x6E, 0x5F]
            + [0xFB, 0x3F, 0xF8, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
        var sut = BinaryEncoder()

        sut.encode(uuid)
        sut.encode(Date(timeIntervalSinceReferenceDate: 1.5))

        #expect(sut.bytes == expected)
    }

    @Test("An optional of an optional wraps a value written as null in a one-element array, so .some(nil) reads back as itself")
    func nestedOptional() throws {
        let values: [Int??] = [.none, .some(.none), .some(.some(4))]
        let expected: [UInt8] = [0xF6, 0x81, 0xF6, 0x04]
        var encoder = BinaryEncoder()
        for value in values {
            encoder.encode(value)
        }
        var sut = BinaryDecoder(encoder.bytes)

        let actual = try values.map { _ in try sut.decode(Int??.self) }

        #expect(encoder.bytes == expected)
        #expect(actual == values)
        #expect(sut.isAtEnd)
    }

    @Test("An optional Sensitive of an optional holding nil reads back as itself, not as nil")
    func optionalSensitiveOfOptional() throws {
        let values: [Sensitive<Int?>?] = [.none, .some(Sensitive(nil)), .some(Sensitive(3))]
        let expected: [Int??] = [.none, .some(.none), .some(.some(3))]
        var encoder = BinaryEncoder(writingSensitiveValues: true)
        for value in values {
            encoder.encode(value)
        }
        var sut = BinaryDecoder(encoder.bytes[...], readingSensitiveValues: true)

        let actual: [Int??] = try values.map { _ in try sut.decode(Sensitive<Int?>?.self).map { $0.value } }

        #expect(actual == expected)
        #expect(sut.isAtEnd)
    }

    enum AnyCount: Refinement {
        static let constraints: [Constraint<Int?>] = []
    }

    @Test("An optional Refined of an optional holding nil reads back as itself, not as nil")
    func optionalRefinedOfOptional() throws {
        let values: [Refined<Int?, AnyCount>?] = [.none, .some(try Refined(nil)), .some(try Refined(3))]
        var encoder = BinaryEncoder()
        for value in values {
            encoder.encode(value)
        }
        var sut = BinaryDecoder(encoder.bytes)

        let actual = try values.map { _ in try sut.decode(Refined<Int?, AnyCount>?.self) }

        #expect(actual == values)
        #expect(sut.isAtEnd)
    }

    @Test("An optional array of one element is wrapped too, as its head is the wrapper's, and reads back as itself")
    func optionalArrayOfOne() throws {
        let values: [[Int]?] = [[5], [], nil]
        let expected: [UInt8] = [0x81, 0x81, 0x05, 0x80, 0xF6]
        var encoder = BinaryEncoder()
        for value in values {
            encoder.encode(value)
        }
        var sut = BinaryDecoder(encoder.bytes)

        let actual = try values.map { _ in try sut.decode([Int]?.self) }

        #expect(encoder.bytes == expected)
        #expect(actual == values)
        #expect(sut.isAtEnd)
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

    @Test("A Double reads a single-precision float too, widened")
    func doubleFromFloat() throws {
        let bytes: [UInt8] = [0xFA, 0x47, 0xC3, 0x50, 0x00]
        let expected = 100_000.0
        var sut = BinaryDecoder(bytes)

        let actual = try sut.decode(Double.self)

        #expect(actual == expected)
    }

    @Test("An integer's head of a wider width than it needs still reads")
    func longHead() throws {
        let bytes: [UInt8] = [0x1B, 0, 0, 0, 0, 0, 0, 0, 0x07]
        let expected: UInt8 = 7
        var sut = BinaryDecoder(bytes)

        let actual = try sut.decode(UInt8.self)

        #expect(actual == expected)
        #expect(sut.isAtEnd)
    }

    @Test("An integer past the type's range throws invalidValue: 256 for a UInt8, -129 for an Int8, -1 for a UInt")
    func integerOutOfRange() {
        let cases: [[UInt8]] = [[0x19, 0x01, 0x00], [0x38, 0x80], [0x20]]
        var uint8 = BinaryDecoder(cases[0])
        var int8 = BinaryDecoder(cases[1])
        var unsigned = BinaryDecoder(cases[2])

        #expect(throws: BinaryDecodingError.invalidValue) {
            _ = try uint8.decode(UInt8.self)
        }
        #expect(throws: BinaryDecodingError.invalidValue) {
            _ = try int8.decode(Int8.self)
        }
        #expect(throws: BinaryDecodingError.invalidValue) {
            _ = try unsigned.decode(UInt.self)
        }
    }

    @Test("The bounds of a type's range read back: 255 for a UInt8, -128 and 127 for an Int8")
    func integerRangeBounds() throws {
        let bytes: [UInt8] = [0x18, 0xFF, 0x38, 0x7F, 0x18, 0x7F]
        var sut = BinaryDecoder(bytes)

        #expect(try sut.decode(UInt8.self) == 255)
        #expect(try sut.decode(Int8.self) == -128)
        #expect(try sut.decode(Int8.self) == 127)
        #expect(sut.isAtEnd)
    }

    @Test("A value of another kind than the type throws typeMismatch: a string for an integer, an integer for a string, a Bool or a float")
    func typeMismatch() {
        let text: [UInt8] = [0x61, 0x61]
        let integer: [UInt8] = [0x01]
        var integerFromText = BinaryDecoder(text)
        var stringFromInteger = BinaryDecoder(integer)
        var boolFromInteger = BinaryDecoder(integer)
        var doubleFromInteger = BinaryDecoder(integer)
        var floatFromDouble = BinaryDecoder([0xFB, 0, 0, 0, 0, 0, 0, 0, 0])
        var arrayFromText = BinaryDecoder(text)

        #expect(throws: BinaryDecodingError.typeMismatch) {
            _ = try integerFromText.decode(Int.self)
        }
        #expect(throws: BinaryDecodingError.typeMismatch) {
            _ = try stringFromInteger.decode(String.self)
        }
        #expect(throws: BinaryDecodingError.typeMismatch) {
            _ = try boolFromInteger.decode(Bool.self)
        }
        #expect(throws: BinaryDecodingError.typeMismatch) {
            _ = try doubleFromInteger.decode(Double.self)
        }
        #expect(throws: BinaryDecodingError.typeMismatch) {
            _ = try floatFromDouble.decode(Float.self)
        }
        #expect(throws: BinaryDecodingError.typeMismatch) {
            _ = try arrayFromText.decode([Int].self)
        }
    }

    @Test("A head CBOR reserves, or an indefinite length, throws invalidValue")
    func reservedHead() {
        let reserved: [UInt8] = [0x1C]
        let indefinite: [UInt8] = [0x7F, 0x61, 0x61, 0xFF]
        var fromReserved = BinaryDecoder(reserved)
        var fromIndefinite = BinaryDecoder(indefinite)

        #expect(throws: BinaryDecodingError.invalidValue) {
            _ = try fromReserved.decode(Int.self)
        }
        #expect(throws: BinaryDecodingError.invalidValue) {
            _ = try fromIndefinite.decode(String.self)
        }
    }

    @Test("Reading past the end throws endOfData: a head whose argument is cut short")
    func endOfData() {
        let bytes: [UInt8] = [0x1A, 1, 2, 3]
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
        let bytes: [UInt8] = [0xD8, 0x25, 0x50] + [UInt8](repeating: 7, count: 15)
        var sut = BinaryDecoder(bytes)

        #expect(throws: BinaryDecodingError.endOfData) {
            _ = try sut.decode(UUID.self)
        }
    }

    @Test("A UUID with another tag, or a byte string of another length, throws invalidValue")
    func uuidWrongTagOrLength() {
        let wrongTag: [UInt8] = [0xD8, 0x24, 0x50] + [UInt8](repeating: 7, count: 16)
        let wrongLength: [UInt8] = [0xD8, 0x25, 0x4F] + [UInt8](repeating: 7, count: 15)
        var fromWrongTag = BinaryDecoder(wrongTag)
        var fromWrongLength = BinaryDecoder(wrongLength)

        #expect(throws: BinaryDecodingError.invalidValue) {
            _ = try fromWrongTag.decode(UUID.self)
        }
        #expect(throws: BinaryDecodingError.invalidValue) {
            _ = try fromWrongLength.decode(UUID.self)
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
        let bytes: [UInt8] = [0x65, 0x61, 0x62]
        var sut = BinaryDecoder(bytes)

        #expect(throws: BinaryDecodingError.endOfData) {
            _ = try sut.decode(String.self)
        }
    }

    @Test("A string count that is exactly the bytes left reads them all")
    func stringCountAtEnd() throws {
        let bytes: [UInt8] = [0x62, 0x61, 0x62]
        let expected = "ab"
        var sut = BinaryDecoder(bytes)

        let actual = try sut.decode(String.self)

        #expect(actual == expected)
        #expect(sut.isAtEnd)
    }

    @Test("An array whose count is more than the bytes left throws endOfData before reading elements")
    func arrayCountPastEnd() {
        let bytes: [UInt8] = [0x9A, 0xFF, 0xFF, 0xFF, 0xFF, 1]
        var sut = BinaryDecoder(bytes)

        #expect(throws: BinaryDecodingError.endOfData) {
            _ = try sut.decode([UInt8].self)
        }
    }

    @Test("A string that isn't UTF-8 throws invalidValue")
    func invalidUTF8() {
        let bytes: [UInt8] = [0x61, 0xFF]
        var sut = BinaryDecoder(bytes)

        #expect(throws: BinaryDecodingError.invalidValue) {
            _ = try sut.decode(String.self)
        }
    }

    @Test("A Bool from a simple value other than true or false throws typeMismatch")
    func invalidBool() {
        let bytes: [UInt8] = [0xF6]
        var sut = BinaryDecoder(bytes)

        #expect(throws: BinaryDecodingError.typeMismatch) {
            _ = try sut.decode(Bool.self)
        }
    }

    @Test("An optional of another kind than its wrapped type, not null, throws what the wrapped type throws")
    func invalidOptional() {
        let bytes: [UInt8] = [0xF7]
        var sut = BinaryDecoder(bytes)

        #expect(throws: BinaryDecodingError.typeMismatch) {
            _ = try sut.decode(UInt8?.self)
        }
    }

    @Test("A decoder over a slice reads from the slice's start")
    func slice() throws {
        let bytes: [UInt8] = [9, 9, 0x07]
        let expected: UInt16 = 7
        var sut = BinaryDecoder(bytes[2...])

        let actual = try sut.decode(UInt16.self)

        #expect(actual == expected)
        #expect(sut.isAtEnd)
    }
}
