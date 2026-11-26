import Benchmark
// The CBOR package comes through Persistence, which links it: BENCHMARKS in scripts/modules.py
// lists only this package's own modules, and the store writes with the same coder.
import CBOR
import EventMacros

@Event
struct Tapped {
    var number: Int
    var screen: String
    var coupon: String?
    var express: Bool
}

// The hand-written form the generated conformance must keep pace with: the same fields, with a
// Codable conformance written by hand as Swift's documentation shows.
struct HandWrittenTapped: Event, Codable {
    var number: Int
    var screen: String
    var coupon: String?
    var express: Bool

    private enum CodingKeys: String, CodingKey {
        case number, screen, coupon, express
    }

    init(number: Int, screen: String, coupon: String?, express: Bool) {
        self.number = number
        self.screen = screen
        self.coupon = coupon
        self.express = express
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(number, forKey: .number)
        try container.encode(screen, forKey: .screen)
        try container.encodeIfPresent(coupon, forKey: .coupon)
        try container.encode(express, forKey: .express)
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        number = try container.decode(Int.self, forKey: .number)
        screen = try container.decode(String.self, forKey: .screen)
        coupon = try container.decodeIfPresent(String.self, forKey: .coupon)
        express = try container.decode(Bool.self, forKey: .express)
    }
}

// The positional encoding the keyed one replaced, written by hand with no library code: each field's
// bytes one after another, no names or type tags (little-endian 64-bit integers, a string as its
// UTF-8 count as a UInt32 then its bytes, an optional as a byte, 0 or 1, before the value, a Bool as
// one byte). D9 in .kanban/triage.md holds the keyed encoding to twice its instructions, with a
// one-time exception for the record coder, Codable over the CBOR package (TRAF-83), whose
// numbers it records.
struct PositionalTapped {
    var number: Int
    var screen: String
    var coupon: String?
    var express: Bool

    func encode(to bytes: inout [UInt8]) {
        bytes.appendLittleEndian(Int64(number))
        bytes.appendCounted(screen)
        if let coupon {
            bytes.append(1)
            bytes.appendCounted(coupon)
        } else {
            bytes.append(0)
        }
        bytes.append(express ? 1 : 0)
    }

    init(number: Int, screen: String, coupon: String?, express: Bool) {
        self.number = number
        self.screen = screen
        self.coupon = coupon
        self.express = express
    }

    init(from reader: inout PositionalReader) throws(PositionalReader.Failure) {
        number = Int(try reader.readInt64())
        screen = try reader.readString()
        coupon = try reader.readByte() == 1 ? try reader.readString() : nil
        express = try reader.readByte() == 1
    }
}

extension [UInt8] {
    fileprivate mutating func appendLittleEndian(_ value: Int64) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    fileprivate mutating func appendCounted(_ string: String) {
        var string = string
        string.withUTF8 { utf8 in
            Swift.withUnsafeBytes(of: UInt32(utf8.count).littleEndian) { append(contentsOf: $0) }
            append(contentsOf: utf8)
        }
    }
}

/// Reads `PositionalTapped`'s fields, checking each against the bytes left, as a decoder must.
struct PositionalReader {
    struct Failure: Error {}

    let bytes: [UInt8]
    var position = 0

    mutating func readByte() throws(Failure) -> UInt8 {
        guard position < bytes.count else { throw Failure() }
        defer { position += 1 }
        return bytes[position]
    }

    mutating func readInt64() throws(Failure) -> Int64 {
        guard bytes.count - position >= 8 else { throw Failure() }
        defer { position += 8 }
        let start = position
        return bytes.withUnsafeBytes { Int64(littleEndian: $0.loadUnaligned(fromByteOffset: start, as: Int64.self)) }
    }

    mutating func readString() throws(Failure) -> String {
        guard bytes.count - position >= 4 else { throw Failure() }
        let start = position
        let count = Int(bytes.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: start, as: UInt32.self)) })
        position += 4
        guard bytes.count - position >= count else { throw Failure() }
        defer { position += count }
        guard let string = String(validating: bytes[position ..< position + count], as: UTF8.self) else { throw Failure() }
        return string
    }
}

let benchmarks: @Sendable () -> Void = {
    Benchmark.defaultConfiguration.metrics = [.wallClock, .mallocCountTotal]
    Benchmark.defaultConfiguration.maxDuration = .seconds(2)

    let count = 1_000
    // Built before each window, so only the coding is measured. Each event is its own CBOR item,
    // as a store writes each record.
    let handWritten = (0 ..< count).map { HandWrittenTapped(number: $0, screen: "Checkout", coupon: $0.isMultiple(of: 3) ? "SPRING" : nil, express: $0.isMultiple(of: 2)) }
    let generated = (0 ..< count).map { Tapped(number: $0, screen: "Checkout", coupon: $0.isMultiple(of: 3) ? "SPRING" : nil, express: $0.isMultiple(of: 2)) }
    let encoder = CBOREncoder()
    let decoder = CBORDecoder()
    // Benchmark setup, not library code: an encoding that fails here is a broken benchmark.
    let handWrittenBytes = handWritten.map { try! encoder.encode($0) }
    let generatedBytes = generated.map { try! encoder.encode($0) }
    let positional = (0 ..< count).map { PositionalTapped(number: $0, screen: "Checkout", coupon: $0.isMultiple(of: 3) ? "SPRING" : nil, express: $0.isMultiple(of: 2)) }
    var positionalBytes: [UInt8] = []
    positional.forEach { $0.encode(to: &positionalBytes) }

    // MARK: encode: a thousand events.

    Benchmark("encode: BASELINE positional encoding") { benchmark in
        for _ in benchmark.scaledIterations {
            var bytes: [UInt8] = []
            for event in positional {
                event.encode(to: &bytes)
            }
            blackHole(bytes)
        }
    }

    Benchmark("encode: BASELINE hand-written conformance") { benchmark in
        for _ in benchmark.scaledIterations {
            for event in handWritten {
                blackHole(try encoder.encode(event))
            }
        }
    }

    Benchmark("encode: @Event conformance") { benchmark in
        for _ in benchmark.scaledIterations {
            for event in generated {
                blackHole(try encoder.encode(event))
            }
        }
    }

    // MARK: decode: a thousand events.

    Benchmark("decode: BASELINE positional encoding") { benchmark in
        for _ in benchmark.scaledIterations {
            var reader = PositionalReader(bytes: positionalBytes)
            for _ in 0 ..< count {
                blackHole(try PositionalTapped(from: &reader))
            }
        }
    }

    Benchmark("decode: BASELINE hand-written conformance") { benchmark in
        for _ in benchmark.scaledIterations {
            for bytes in handWrittenBytes {
                blackHole(try decoder.decode(HandWrittenTapped.self, from: bytes))
            }
        }
    }

    Benchmark("decode: @Event conformance") { benchmark in
        for _ in benchmark.scaledIterations {
            for bytes in generatedBytes {
                blackHole(try decoder.decode(Tapped.self, from: bytes))
            }
        }
    }
}
