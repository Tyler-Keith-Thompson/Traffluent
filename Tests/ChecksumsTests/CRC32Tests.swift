import Checksums
import Testing
import TraffluentTestSupport

@Suite("CRC32")
struct CRC32Tests {
    @Test(
        "The checksum of a string's UTF-8 matches its known CRC-32",
        arguments: [
            ("123456789", 0xCBF4_3926),
            ("This is a test string", 1_800_336_237),
            ("short", 2_401_800_354),
            (
                "Quite long ascii message, see the thing about ascii is that it has these nice predictable english letters that make it trivial to do work with, so it's friendly.",
                3_256_568_170
            ),
            ("אני בעצם לא יודע עברית, אבל אולי דניאל יקבל מזה בעיטה", 191_699_852),
            ("a", 0xE8B7_BE43),
        ] as [(String, UInt32)]
    )
    func knownVectors(text: String, expected: UInt32) {
        let bytes = Array(text.utf8)

        let actual = bytes.withUnsafeBytes { CRC32.checksum(of: $0) }

        #expect(actual == expected)
    }

    @Test("The checksum of no bytes is 0")
    func empty() {
        let expected: UInt32 = 0
        let bytes: [UInt8] = []

        let actual = bytes.withUnsafeBytes { CRC32.checksum(of: $0) }

        #expect(actual == expected)
    }

    @Test("A new checksum is that of no bytes")
    func newChecksum() {
        let expected: UInt32 = 0

        let actual = CRC32().checksum

        #expect(actual == expected)
    }

    @Test("Updating in two pieces, split anywhere, gives the checksum of the whole")
    func pieces() {
        let bytes = Array("Quite long ascii message, see the thing about ascii".utf8)
        let expected = bytes.withUnsafeBytes { CRC32.checksum(of: $0) }

        for split in 0...bytes.count {
            var sut = CRC32()

            bytes[..<split].withUnsafeBytes { sut.update(with: $0) }
            bytes[split...].withUnsafeBytes { sut.update(with: $0) }

            #expect(sut.checksum == expected, "split at \(split)")
        }
    }

    @Test("Every length from 0 through 24, across the 8-byte steps and their tails, matches a bitwise CRC-32")
    func lengthsAroundTheStep() {
        let all = (0..<24).map { UInt8(truncatingIfNeeded: $0 &* 37 &+ 11) }

        for length in 0...all.count {
            let bytes = Array(all[..<length])
            let expected = bitwiseCRC32(bytes)

            let actual = bytes.withUnsafeBytes { CRC32.checksum(of: $0) }

            #expect(actual == expected, "length \(length)")
        }
    }

    @Test("Every single byte value matches a bitwise CRC-32")
    func everyByte() {
        for value in UInt8.min...UInt8.max {
            let expected = bitwiseCRC32([value])

            let actual = [value].withUnsafeBytes { CRC32.checksum(of: $0) }

            #expect(actual == expected, "byte \(value)")
        }
    }

    @Test("Checksums of the same bytes are equal, and of different bytes differ", .tags(.conformance))
    func equality() {
        var first = CRC32()
        var second = CRC32()
        var third = CRC32()

        [UInt8(1), 2, 3].withUnsafeBytes { first.update(with: $0) }
        [UInt8(1), 2, 3].withUnsafeBytes { second.update(with: $0) }
        [UInt8(1), 2, 4].withUnsafeBytes { third.update(with: $0) }

        #expect(first == second)
        #expect(first.hashValue == second.hashValue)
        #expect(first != third)
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
