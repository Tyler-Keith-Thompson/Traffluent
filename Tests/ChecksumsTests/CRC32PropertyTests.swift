// Property tests against a naive reference: the sliced-by-8 checksum equals the bitwise one, for
// any bytes fed in any two pieces.

import Checksums
import PropertyBased
import Testing
import TraffluentTestSupport

@Suite("CRC32: properties")
struct CRC32PropertyTests {
    @Test("The checksum of any bytes equals the bitwise CRC-32", .tags(.randomized))
    func matchesBitwise() async {
        await propertyCheck(count: 500, input: Gen.uint8().array(of: 0...300)) { bytes in
            let expected = bitwiseCRC32(bytes)

            let actual = bytes.withUnsafeBytes { CRC32.checksum(of: $0) }

            #expect(actual == expected)
        }
    }

    @Test("Any bytes fed in two pieces checksum as the whole does", .tags(.randomized))
    func piecesMatchWhole() async {
        await propertyCheck(count: 500, input: Gen.uint8().array(of: 0...300), Gen.int(in: 0...300)) { bytes, cut in
            let split = min(cut, bytes.count)
            let expected = bitwiseCRC32(bytes)
            var sut = CRC32()

            bytes[..<split].withUnsafeBytes { sut.update(with: $0) }
            bytes[split...].withUnsafeBytes { sut.update(with: $0) }

            #expect(sut.checksum == expected)
        }
    }
}

/// CRC-32 one bit at a time, with no tables: the definition, as a reference.
private func bitwiseCRC32(_ bytes: [UInt8]) -> UInt32 {
    var crc: UInt32 = 0xFFFF_FFFF
    for byte in bytes {
        crc ^= UInt32(byte)
        for _ in 0..<8 {
            crc = crc & 1 == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1
        }
    }
    return ~crc
}
