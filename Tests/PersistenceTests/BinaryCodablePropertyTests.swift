// Property tests against a naive reference: what is encoded decodes to the same values, and the
// bytes are the reference layout (little-endian fixed-width integers, counted UTF-8).

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

    @Test("An integer's bytes are its value's, least significant first", .tags(.randomized))
    func integerBytes() async {
        await propertyCheck(count: 300, input: Gen.uint64(in: .min ... .max)) { value in
            let expected = (0..<8).map { UInt8(truncatingIfNeeded: value >> (8 * $0)) }
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
}
