// Property tests against a naive reference: what is encoded decodes to the same values, the bytes
// are RFC 8949's layout (an integer's head in the fewest bytes), and a map read by key gives what a
// dictionary of the entries written would.

import Persistence
import PropertyBased
import Testing
import TraffluentTestSupport

@Suite("BinaryCodable: properties")
struct BinaryCodablePropertyTests {
    @Test("Any integers, strings and arrays decode to the values encoded", .tags(.randomized))
    func roundTrip() async {
        await propertyCheck(count: 300, input: Gen.int(in: .min ... .max), Gen.int32(in: .min ... .max), Gen.uint8().array(of: 0...20)) { word, small, bytes in
            let text = String(decoding: bytes.map { $0 % 128 }, as: UTF8.self)
            var encoder = BinaryEncoder()
            encoder.encode(word)
            encoder.encode(small)
            encoder.encode(text)
            encoder.encode(bytes)
            encoder.encode(Optional(small))
            var sut = BinaryDecoder(encoder.bytes)

            #expect((try? sut.decode(Int.self)) == word)
            #expect((try? sut.decode(Int32.self)) == small)
            #expect((try? sut.decode(String.self)) == text)
            #expect((try? sut.decode([UInt8].self)) == bytes)
            #expect((try? sut.decode(Int32?.self)) == small)
            #expect(sut.isAtEnd)
        }
    }

    @Test("An integer is its CBOR head: the argument inline below 24, else in the fewest of 1, 2, 4 or 8 bytes, most significant first", .tags(.randomized))
    func integerBytes() async {
        await propertyCheck(count: 300, input: Gen.uint64(in: .min ... .max), Gen.int(in: 0 ... 63)) { full, shift in
            // Shifted, so every width of head comes up, not only the 8-byte one.
            let value = full >> UInt64(shift)
            let width = value < 24 ? 0 : value <= 0xFF ? 1 : value <= 0xFFFF ? 2 : value <= 0xFFFF_FFFF ? 4 : 8
            let information: [Int: UInt8] = [1: 24, 2: 25, 4: 26, 8: 27]
            let head: UInt8 = width == 0 ? UInt8(value) : information[width]!
            let expected = [head] + (0 ..< width).reversed().map { UInt8(truncatingIfNeeded: value >> (8 * UInt64($0))) }
            var sut = BinaryEncoder()

            sut.encode(value)

            #expect(sut.bytes == expected)
        }
    }

    @Test("Bytes cut short of a value throw rather than read past the end", .tags(.randomized))
    func truncated() async {
        await propertyCheck(count: 300, input: Gen.uint8().array(of: 0...20), Gen.int(in: 0...100)) { bytes, cut in
            var encoder = BinaryEncoder()
            encoder.encode(bytes)
            let keep = cut % encoder.bytes.count
            var sut = BinaryDecoder(Array(encoder.bytes[..<keep]))

            #expect(throws: BinaryDecodingError.endOfData) {
                _ = try sut.decode([UInt8].self)
            }
        }
    }

    @Test("A map written with any subset of its keys, in any order, beside unknown ones, reads each key's value, or nil for one left out", .tags(.randomized))
    func keyedSubset() async {
        await propertyCheck(count: 300, input: Gen.int(in: .min ... .max), Gen.bool, Gen.int(in: 0 ... 7), Gen.int(in: 0 ... 5), Gen.int(in: 0 ... 3)) { number, flag, present, order, unknown in
            let text = "t\(number % 100)"
            // The reference: the keys written.
            var written: Set<String> = []
            var encoder = BinaryEncoder()
            encoder.encodeMap { map in
                let entries: [(key: String, write: (inout KeyedBinaryEncoder) -> Void)] = [
                    ("number", { $0.encode(number, forKey: "number") }),
                    ("text", { $0.encode(text, forKey: "text") }),
                    ("flag", { $0.encode(flag, forKey: "flag") }),
                ]
                let permutations = [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]]
                for _ in 0 ..< unknown {
                    map.encode([number, number], forKey: "unknown")
                }
                for index in permutations[order] where present & (1 << index) != 0 {
                    entries[index].write(&map)
                    written.insert(entries[index].key)
                }
            }
            var decoder = BinaryDecoder(encoder.bytes)

            var sut = try? decoder.decodeMap()
            let actualNumber: Int?? = try? sut?.decode(Int?.self, forKey: "number")
            let actualText: String?? = try? sut?.decode(String?.self, forKey: "text")
            let actualFlag: Bool?? = try? sut?.decode(Bool?.self, forKey: "flag")

            let expectedNumber: Int? = written.contains("number") ? number : nil
            let expectedText: String? = written.contains("text") ? text : nil
            let expectedFlag: Bool? = written.contains("flag") ? flag : nil
            #expect(actualNumber == .some(expectedNumber))
            #expect(actualText == .some(expectedText))
            #expect(actualFlag == .some(expectedFlag))
            #expect(decoder.isAtEnd)
        }
    }
}
