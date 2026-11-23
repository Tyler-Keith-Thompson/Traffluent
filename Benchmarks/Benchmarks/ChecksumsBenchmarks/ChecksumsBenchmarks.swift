import Benchmark
import Checksums

let benchmarks: @Sendable () -> Void = {
    Benchmark.defaultConfiguration.metrics = [.wallClock, .mallocCountTotal]
    Benchmark.defaultConfiguration.maxDuration = .seconds(2)

    // A tracked record's frame is about this size; a whole segment is the other end.
    let record = bytes(count: 128)
    let segment = bytes(count: 64 * 1024)
    let repetitions = 1_000

    // MARK: CRC-32 of a record-sized buffer.

    // The hand-written form the library must keep pace with: the table-driven loop, one byte at
    // a time.
    Benchmark("CRC32 128 B: BASELINE byte-at-a-time table") { benchmark in
        for _ in benchmark.scaledIterations {
            for _ in 0 ..< repetitions {
                blackHole(record.withUnsafeBytes { byteAtATime($0) })
            }
        }
    }

    Benchmark("CRC32 128 B: checksum(of:)") { benchmark in
        for _ in benchmark.scaledIterations {
            for _ in 0 ..< repetitions {
                blackHole(record.withUnsafeBytes { CRC32.checksum(of: $0) })
            }
        }
    }

    // MARK: CRC-32 of a segment-sized buffer.

    Benchmark("CRC32 64 KiB: BASELINE byte-at-a-time table") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(segment.withUnsafeBytes { byteAtATime($0) })
        }
    }

    Benchmark("CRC32 64 KiB: checksum(of:)") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(segment.withUnsafeBytes { CRC32.checksum(of: $0) })
        }
    }
}

/// Bytes the optimizer can't see through.
@inline(never)
func bytes(count: Int) -> [UInt8] {
    (0 ..< count).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) }
}

let table: [UInt32] = (0 ... 255).map { byte in
    (0 ..< 8).reduce(UInt32(byte)) { value, _ in value & 1 == 0 ? value >> 1 : 0xEDB8_8320 ^ (value >> 1) }
}

/// CRC-32 one byte at a time through a 256-entry table.
@inline(never)
func byteAtATime(_ bytes: UnsafeRawBufferPointer) -> UInt32 {
    table.withUnsafeBufferPointer { table in
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc = (crc >> 8) ^ table[Int((crc ^ UInt32(byte)) & 0xFF)]
        }
        return ~crc
    }
}
