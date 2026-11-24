import Persistence
import Testing

@Suite("BinaryCodable: maps")
struct KeyedBinaryCodingTests {
    @Test("Keys read in another order than they were written read their own values")
    func reordered() throws {
        var encoder = BinaryEncoder()
        encoder.encodeMap { map in
            map.encode(1, forKey: "first")
            map.encode("two", forKey: "second")
            map.encode(true, forKey: "third")
        }
        var decoder = BinaryDecoder(encoder.bytes)
        var sut = try decoder.decodeMap()

        let third: Bool = try sut.decode(forKey: "third")
        let first: Int = try sut.decode(forKey: "first")
        let second: String = try sut.decode(forKey: "second")

        #expect(third == true)
        #expect(first == 1)
        #expect(second == "two")
        #expect(decoder.isAtEnd)
    }

    @Test("A missing key read with a default gives the default; a present one its value, wherever it is in the map")
    func defaultWhenMissing() throws {
        let expectedMissing = "USD"
        let expectedPresent = 7
        var encoder = BinaryEncoder()
        encoder.encodeMap { map in
            map.encode(1, forKey: "first")
            map.encode(expectedPresent, forKey: "present")
        }
        var decoder = BinaryDecoder(encoder.bytes)
        var sut = try decoder.decodeMap()

        let missing: String = try sut.decode(forKey: "currency", default: "USD")
        let present: Int = try sut.decode(forKey: "present", default: 0)
        let first: Int = try sut.decode(forKey: "first", default: 0)

        #expect(missing == expectedMissing)
        #expect(present == expectedPresent)
        #expect(first == 1)
        #expect(decoder.isAtEnd)
    }

    @Test("A null entry read with a default is the value's own reading of null: nil for an optional, typeMismatch otherwise")
    func defaultNotForNull() throws {
        var encoder = BinaryEncoder()
        encoder.encodeMap { map in
            map.encode(String?.none, forKey: "coupon")
            map.encode(String?.none, forKey: "currency")
        }
        let expectedError = BinaryDecodingError.typeMismatch
        var decoder = BinaryDecoder(encoder.bytes)
        var sut = try decoder.decodeMap()

        let coupon: String? = try sut.decode(forKey: "coupon", default: "WELCOME")
        func decodeCurrency() throws(BinaryDecodingError) {
            let _: String = try sut.decode(forKey: "currency", default: "USD")
        }

        #expect(coupon == nil)
        #expect(throws: expectedError) { try decodeCurrency() }
    }

    @Test("An entry whose key is never read is skipped, nested arrays, maps and tags included, and the decoder moves past the whole map")
    func unknownKeySkipped() throws {
        let expected = "after"
        var encoder = BinaryEncoder()
        encoder.encodeMap { map in
            map.encode([[1, 2], [3]], forKey: "removed")
            map.encode(7, forKey: "kept")
            map.encode(Payload(), forKey: "alsoRemoved")
        }
        encoder.encode(expected)
        var decoder = BinaryDecoder(encoder.bytes)
        var sut = try decoder.decodeMap()

        let kept: Int = try sut.decode(forKey: "kept")
        let actual: String = try decoder.decode()

        #expect(kept == 7)
        #expect(actual == expected)
        #expect(decoder.isAtEnd)
    }

    @Test("An entry never read whose value's head takes more than a byte, a 300-byte string, is skipped whole")
    func longUnknownValueSkipped() throws {
        let removed = String(repeating: "x", count: 300)
        var encoder = BinaryEncoder()
        encoder.encodeMap { map in
            map.encode(removed, forKey: "removed")
        }
        encoder.encode(7)
        var decoder = BinaryDecoder(encoder.bytes)
        _ = try decoder.decodeMap()

        let actual: Int = try decoder.decode()

        #expect(actual == 7)
        #expect(decoder.isAtEnd)
    }

    @Test("A map whose arrays declare more items than the bytes left could hold, counting the ones already pending, throws invalidValue rather than count them")
    func pendingItemsBounded() throws {
        // {"x": [[0, 0]]} with the outer array declaring two elements: once the inner array's head
        // is read, two bytes are left for the outer array's second element and the inner's two.
        let bytes: [UInt8] = [0xA1, 0x61, 0x78, 0x82, 0x82, 0x00, 0x00]
        var sut = BinaryDecoder(bytes)

        #expect(throws: BinaryDecodingError.invalidValue) {
            _ = try sut.decodeMap()
        }
    }

    @Test("An optional whose key is missing reads nil, and the keys after it still read in place")
    func missingOptional() throws {
        var encoder = BinaryEncoder()
        encoder.encodeMap { map in
            map.encode(1, forKey: "a")
            map.encode(3, forKey: "c")
        }
        var decoder = BinaryDecoder(encoder.bytes)
        var sut = try decoder.decodeMap()

        let a: Int = try sut.decode(forKey: "a")
        let b: Int? = try sut.decode(forKey: "b")
        let c: Int = try sut.decode(forKey: "c")

        #expect(a == 1)
        #expect(b == nil)
        #expect(c == 3)
    }

    @Test("A key looked up after a map's last entry is read is missing, even when the items after the map spell it")
    func pastLastEntry() throws {
        var encoder = BinaryEncoder()
        encoder.encodeMap { map in
            map.encode(1, forKey: "a")
        }
        encoder.encode("b")
        encoder.encode(2)
        var decoder = BinaryDecoder(encoder.bytes)
        var sut = try decoder.decodeMap()
        let a: Int = try sut.decode(forKey: "a")

        let actual: Int? = try sut.decode(forKey: "b")

        #expect(a == 1)
        #expect(actual == nil)
    }

    @Test("An optional under its key holding null reads nil; one holding a value reads it")
    func optionalPresent() throws {
        var encoder = BinaryEncoder()
        encoder.encodeMap { map in
            map.encode(String?.none, forKey: "none")
            map.encode(String?.some("x"), forKey: "some")
        }
        var decoder = BinaryDecoder(encoder.bytes)
        var sut = try decoder.decodeMap()

        let none: String? = try sut.decode(forKey: "none")
        let some: String? = try sut.decode(forKey: "some")

        #expect(none == nil)
        #expect(some == "x")
    }

    @Test("A non-optional value whose key is missing throws keyNotFound; so does any key of an empty map")
    func missingRequired() throws {
        var encoder = BinaryEncoder()
        encoder.encodeMap { map in
            map.encode(1, forKey: "a")
        }
        encoder.encodeMap { _ in }
        var decoder = BinaryDecoder(encoder.bytes)
        var sut = try decoder.decodeMap()
        var empty = try decoder.decodeMap()

        #expect(throws: BinaryDecodingError.keyNotFound) {
            let _: Int = try sut.decode(forKey: "b")
        }
        #expect(throws: BinaryDecodingError.keyNotFound) {
            let _: Int = try empty.decode(forKey: "a")
        }
        #expect(try sut.decode(Int.self, forKey: "a") == 1)
    }

    @Test("A key is matched by all its bytes: a key that is a prefix of another, or longer, doesn't match")
    func keyBytes() throws {
        var encoder = BinaryEncoder()
        encoder.encodeMap { map in
            map.encode(1, forKey: "ab")
        }
        var decoder = BinaryDecoder(encoder.bytes)
        var sut = try decoder.decodeMap()

        let short: Int? = try sut.decode(forKey: "a")
        let long: Int? = try sut.decode(forKey: "abc")
        let exact: Int? = try sut.decode(forKey: "ab")

        #expect(short == nil)
        #expect(long == nil)
        #expect(exact == 1)
    }

    @Test("A value of another type under its key throws typeMismatch")
    func typeChanged() throws {
        var encoder = BinaryEncoder()
        encoder.encodeMap { map in
            map.encode("seven", forKey: "count")
        }
        var decoder = BinaryDecoder(encoder.bytes)
        var sut = try decoder.decodeMap()

        #expect(throws: BinaryDecodingError.typeMismatch) {
            let _: Int = try sut.decode(forKey: "count")
        }
    }

    @Test("A map read from a value that isn't one throws typeMismatch")
    func notAMap() {
        let bytes: [UInt8] = [0x80]
        var sut = BinaryDecoder(bytes)

        #expect(throws: BinaryDecodingError.typeMismatch) {
            _ = try sut.decodeMap()
        }
    }

    @Test("A map whose entries run past the end throws endOfData as it is read, before any key is looked up")
    func truncatedMap() {
        let countPastEnd: [UInt8] = [0xA3, 0x61, 0x61, 0x01]
        let valueCut: [UInt8] = [0xA1, 0x61, 0x61, 0x62, 0x78]
        var fromCountPastEnd = BinaryDecoder(countPastEnd)
        var fromValueCut = BinaryDecoder(valueCut)

        #expect(throws: BinaryDecodingError.endOfData) {
            _ = try fromCountPastEnd.decodeMap()
        }
        #expect(throws: BinaryDecodingError.endOfData) {
            _ = try fromValueCut.decodeMap()
        }
    }

    @Test("A key that isn't a text string, which no encoder here writes, never matches and is skipped")
    func integerKey() throws {
        let bytes: [UInt8] = [0xA2, 0x01, 0x61, 0x61, 0x61, 0x61, 0x02]
        let expected = 2
        var decoder = BinaryDecoder(bytes)
        var sut = try decoder.decodeMap()

        let actual: Int = try sut.decode(forKey: "a")

        #expect(actual == expected)
        #expect(decoder.isAtEnd)
    }

    @Test("A map in a map reads by key at each level")
    func nested() throws {
        var encoder = BinaryEncoder()
        encoder.encodeMap { map in
            map.encode(Payload(), forKey: "inner")
            map.encode(5, forKey: "outer")
        }
        var decoder = BinaryDecoder(encoder.bytes)
        var sut = try decoder.decodeMap()

        let outer: Int = try sut.decode(forKey: "outer")
        let inner: Payload = try sut.decode(forKey: "inner")

        #expect(outer == 5)
        #expect(inner == Payload())
    }

    struct Payload: BinaryCodable, Equatable {
        var values: [Int] = [1, 2]

        init() {}

        func encode(to encoder: inout BinaryEncoder) {
            encoder.encodeMap { map in
                map.encode(values, forKey: "values")
            }
        }

        init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
            var map = try decoder.decodeMap()
            values = try map.decode(forKey: "values")
        }
    }
}
