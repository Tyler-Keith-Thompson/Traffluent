# Planted bugs for Checksums; run with `just mutate Checksums`. See scripts/mutate.py.
#
# Each mutant is Mutant(name, file, old, new), where `old` occurs once in Sources/Checksums/<file>
# (or `nth=` picks one), and mode="stmt" replaces whole statements rather than an expression.
# Every mutant must be caught; one that survives needs a test, or a note here saying why it is
# equivalent to the original.
#
# Known equivalent mutants (left out, as they would survive by design):
# - The 8-byte loop's `count - offset >= 8` as `> 8`: a last step of exactly 8 bytes then runs
#   through the byte-at-a-time tail, which computes the same register.

TESTS = ["ChecksumsTests"]

C = "CRC32.swift"

MUTANTS = [
    Mutant("polynomial", C, "0xEDB8_8320 ^ (value >> 1)", "0x04C1_1DB7 ^ (value >> 1)"),
    Mutant("initialzero", C, "register = 0xFFFF_FFFF", "register = 0", mode="stmt"),
    Mutant("nofinalxor", C, "~register", "register"),
    Mutant("staticinitialzero", C, "~advance(0xFFFF_FFFF, over: bytes)", "~advance(0, over: bytes)"),
    Mutant("updateresets", C, "register = Self.advance(register, over: bytes)", "register = Self.advance(0xFFFF_FFFF, over: bytes)", mode="stmt"),
    Mutant("tablesnotchained", C, "(previous >> 8) ^ tables[Int(previous & 0xFF)]", "(previous >> 8)"),
    Mutant("seventables", C, "1..<8", "1..<7"),
    Mutant("stepseven", C, "offset += 8", "offset += 7", mode="stmt"),
    Mutant("registernotfolded", C, "UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self)) ^ crc", "UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self))"),
    Mutant("highwordoffset", C, "offset + 4", "offset + 3"),
    Mutant("tablesswapped", C, "table[7 * 256 + Int(low & 0xFF)]", "table[6 * 256 + Int(low & 0xFF)]"),
    Mutant("lasttablewrong", C, "table[Int(high >> 24)]", "table[256 + Int(high >> 24)]"),
    Mutant("tailshift", C, "crc = (crc >> 8) ^ table[Int((crc ^ UInt32(bytes[offset])) & 0xFF)]", "crc = (crc >> 7) ^ table[Int((crc ^ UInt32(bytes[offset])) & 0xFF)]", mode="stmt"),
    Mutant("tailskipped", C, "offset += 1", "offset += 2", mode="stmt"),
]
