/// The CRC-32 checksum of a run of bytes: the reflected CRC with polynomial `0xEDB88320`, an
/// initial value and final XOR of `0xFFFFFFFF`, as zlib, PNG, gzip and Ethernet compute it.
///
/// Feed it bytes in as many pieces as you like; the checksum is the same as for all of them at
/// once:
///
/// ```swift
/// var crc = CRC32()
/// header.withUnsafeBytes { crc.update(with: $0) }
/// payload.withUnsafeBytes { crc.update(with: $0) }
/// crc.checksum
/// ```
///
/// `"123456789"` checksums to `0xCBF43926`, the algorithm's standard check value.
@frozen
public struct CRC32: Sendable, Hashable {
    /// The register before its final XOR.
    @usableFromInline
    var register: UInt32

    /// A checksum of no bytes yet.
    @inlinable
    public init() {
        register = 0xFFFF_FFFF
    }

    /// The checksum of every byte given so far; `0` for none.
    @inlinable
    public var checksum: UInt32 {
        ~register
    }

    /// Adds `bytes` to the checksum, after the bytes already given.
    ///
    /// - Parameter bytes: The bytes to add.
    /// - Complexity: O(*n*), where *n* is the number of bytes.
    public mutating func update(with bytes: UnsafeRawBufferPointer) {
        register = Self.advance(register, over: bytes)
    }

    /// The checksum of `bytes`.
    ///
    /// - Parameter bytes: The bytes to checksum.
    /// - Returns: Their CRC-32.
    /// - Complexity: O(*n*), where *n* is the number of bytes.
    public static func checksum(of bytes: UnsafeRawBufferPointer) -> UInt32 {
        ~advance(0xFFFF_FFFF, over: bytes)
    }
}

extension CRC32 {
    /// Eight tables of 256 entries, one after another: table 0 is the CRC of each byte value,
    /// and table *k* the CRC of that byte followed by *k* zero bytes.
    ///
    /// Slicing by 8 rather than one byte at a time: it folds eight bytes per step with eight
    /// independent lookups instead of eight dependent ones, which the CPU overlaps.
    /// `ChecksumsBenchmarks` measures it against the byte-at-a-time table loop, its `BASELINE`.
    /// The 8 KiB of tables stay in cache on the hot path that checksums every tracked record.
    fileprivate static let tables: [UInt32] = {
        var tables = [UInt32](repeating: 0, count: 8 * 256)
        for byte in 0..<256 {
            var value = UInt32(byte)
            for _ in 0..<8 {
                value = value & 1 == 0 ? value >> 1 : 0xEDB8_8320 ^ (value >> 1)
            }
            tables[byte] = value
        }
        for table in 1..<8 {
            for byte in 0..<256 {
                let previous = tables[(table - 1) * 256 + byte]
                tables[table * 256 + byte] = (previous >> 8) ^ tables[Int(previous & 0xFF)]
            }
        }
        return tables
    }()

    /// The register after `bytes`, starting from `register`.
    fileprivate static func advance(_ register: UInt32, over bytes: UnsafeRawBufferPointer) -> UInt32 {
        tables.withUnsafeBufferPointer { table in
            var crc = register
            var offset = 0
            let count = bytes.count
            while count - offset >= 8 {
                let low = UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self)) ^ crc
                let high = UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: offset + 4, as: UInt32.self))
                crc = table[7 * 256 + Int(low & 0xFF)]
                    ^ table[6 * 256 + Int((low >> 8) & 0xFF)]
                    ^ table[5 * 256 + Int((low >> 16) & 0xFF)]
                    ^ table[4 * 256 + Int(low >> 24)]
                    ^ table[3 * 256 + Int(high & 0xFF)]
                    ^ table[2 * 256 + Int((high >> 8) & 0xFF)]
                    ^ table[1 * 256 + Int((high >> 16) & 0xFF)]
                    ^ table[Int(high >> 24)]
                offset += 8
            }
            while offset < count {
                crc = (crc >> 8) ^ table[Int((crc ^ UInt32(bytes[offset])) & 0xFF)]
                offset += 1
            }
            return crc
        }
    }
}
