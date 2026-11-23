// SegmentStore's recovery against a model of the segment format: a segment file is built from
// choices (records, delivery marks, records it can't decode, garbage), then damaged (a byte
// flipped, the tail cut, raw bytes appended) or replaced by raw bytes outright, and a store is
// opened on it. The model reads the bytes as the format says (a header, then frames of length,
// CRC-32 and payload, up to the first that isn't intact) and must agree with recovery: the same
// records, in order, each from a frame whose checksum holds, with the redelivery marks the intact
// frames give, and the file cut to the intact prefix, or deleted when nothing is left to deliver.
// A segment whose header names a later version is left as it is, and nothing is read from it.

import Checksums
import Events
import Foundation
import FuzzSupport
import Persistence

struct Tapped: Event, Equatable {
    var number: Int
    var label: String
}

extension Tapped: BinaryCodable {
    func encode(to encoder: inout BinaryEncoder) {
        encoder.encode(number)
        encoder.encode(label)
    }

    init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
        number = try decoder.decode()
        label = try decoder.decode()
    }
}

@main
enum FuzzPersistence {
    static func main() { runFuzzer(fuzz) }

    static let header: [UInt8] = [0x54, 0x52, 0x46, 0x4C, 1, 0, 0, 0]

    /// A frame of `payload`: its length and CRC-32, little-endian, then the payload.
    static func frame(_ payload: [UInt8]) -> [UInt8] {
        let checksum = payload.withUnsafeBytes { CRC32.checksum(of: $0) }
        return littleEndian(UInt32(payload.count)) + littleEndian(checksum) + payload
    }

    static func littleEndian(_ value: UInt32) -> [UInt8] {
        (0 ..< 4).map { UInt8(truncatingIfNeeded: value >> (8 * $0)) }
    }

    /// A record's payload as the format lays it out, for an event named `name` whose fields are
    /// `fields`.
    static func recordPayload(name: String, fields: (inout BinaryEncoder) -> Void) -> [UInt8] {
        var encoder = BinaryEncoder()
        encoder.encode(UInt8(0))
        encoder.encode(Date(timeIntervalSinceReferenceDate: 0))
        encoder.encode("App/File.swift")
        encoder.encode(String?.none)
        encoder.encode("f()")
        encoder.encode(1)
        encoder.encode(1)
        encoder.encode(name)
        fields(&encoder)
        return encoder.bytes
    }

    /// What the model reads from a segment's bytes.
    struct Reading {
        /// Header plus intact frames; 0 when the header isn't the format's.
        var validByteCount = 0
        /// Each intact record frame's number and payload, in order.
        var records: [(index: UInt32, payload: [UInt8])] = []
        var marked: Set<UInt32> = []
        /// Whether the header names a later version than 1, which recovery leaves alone.
        var isNewerVersion = false
    }

    /// The format, read the obvious way.
    static func read(_ bytes: [UInt8]) -> Reading {
        var reading = Reading()
        guard bytes.count >= 8, Array(bytes[0 ..< 4]) == Array(header[0 ..< 4]) else { return reading }
        if Int(bytes[4]) | Int(bytes[5]) << 8 > 1 {
            reading.isNewerVersion = true
            return reading
        }
        guard Array(bytes[0 ..< 8]) == header else { return reading }
        var offset = 8
        reading.validByteCount = 8
        var index: UInt32 = 0
        while bytes.count - offset >= 8 {
            let length = Int(bytes[offset]) | Int(bytes[offset + 1]) << 8 | Int(bytes[offset + 2]) << 16 | Int(bytes[offset + 3]) << 24
            let checksum = UInt32(bytes[offset + 4]) | UInt32(bytes[offset + 5]) << 8 | UInt32(bytes[offset + 6]) << 16 | UInt32(bytes[offset + 7]) << 24
            guard length >= 1, offset + 8 + length <= bytes.count else { break }
            let payload = Array(bytes[offset + 8 ..< offset + 8 + length])
            guard payload.withUnsafeBytes({ CRC32.checksum(of: $0) }) == checksum else { break }
            if payload[0] == 0 {
                reading.records.append((index, Array(payload.dropFirst())))
                index += 1
            } else if payload[0] == 1, (length - 1) % 4 == 0 {
                for start in stride(from: 1, to: length, by: 4) {
                    reading.marked.insert(UInt32(payload[start]) | UInt32(payload[start + 1]) << 8 | UInt32(payload[start + 2]) << 16 | UInt32(payload[start + 3]) << 24)
                }
            } else {
                break
            }
            offset += 8 + length
            reading.validByteCount = offset
        }
        return reading
    }

    static func fuzz(_ input: inout FuzzInput) {
        // Each built payload (without its kind byte) and the event it decodes to, if any.
        var built: [[UInt8]: Tapped?] = [:]
        var bytes: [UInt8]
        if input.int(below: 8) == 0 {
            bytes = []
            while !input.isEmpty { bytes.append(UInt8(input.byte())) }
        } else {
            bytes = input.int(below: 16) == 0 ? [0x54, 0x52, 0x46, 0x4C, UInt8(input.int(below: 3)), 0, 0, 0] : header
            var records: UInt32 = 0
            while !input.isEmpty {
                switch input.int(below: 8) {
                case 0, 1, 2:
                    let event = Tapped(number: input.int(in: -2 ... 2), label: String(repeating: "é", count: input.int(below: 4)))
                    let payload = recordPayload(name: "Tapped") { event.encode(to: &$0) }
                    built[Array(payload.dropFirst())] = event
                    bytes += frame(payload)
                    records += 1
                case 3:
                    // A record the store can't decode: an unlisted type, or bytes past the event's.
                    let payload = input.int(below: 2) == 0
                        ? recordPayload(name: "Other") { _ in }
                        : recordPayload(name: "Tapped") { Tapped(number: 0, label: "").encode(to: &$0); $0.encode(UInt8(9)) }
                    built[Array(payload.dropFirst())] = .some(nil)
                    bytes += frame(payload)
                    records += 1
                case 4:
                    let marked = (0 ..< input.int(in: 1 ... 3)).map { _ in UInt32(input.int(below: Int(records) + 2)) }
                    bytes += frame([1] + marked.flatMap(littleEndian))
                case 5:
                    if !bytes.isEmpty { bytes[input.int(below: bytes.count)] ^= UInt8(1 << input.int(below: 8)) }
                case 6:
                    bytes.removeLast(min(bytes.count, input.int(below: 12)))
                default:
                    for _ in 0 ..< input.int(below: 6) { bytes.append(UInt8(input.byte())) }
                }
            }
        }

        let directory = NSTemporaryDirectory() + "FuzzPersistence-" + UUID().uuidString
        defer { try? FileManager.default.removeItem(atPath: directory) }
        try! FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let path = directory + "/00000000000000000001.segment"
        try! Data(bytes).write(to: URL(fileURLWithPath: path))

        let model = read(bytes)
        var expected: [(event: Tapped, isRedelivered: Bool, frame: Int)] = []
        var collision = false
        for (position, record) in model.records.enumerated() {
            guard let event = built[record.payload] else {
                // An intact frame the fuzzer didn't build means a CRC-32 collision; nothing to compare.
                collision = true
                break
            }
            if let event {
                expected.append((event, model.marked.contains(record.index), position))
            }
        }

        let recovered: [EventRecord]
        do {
            recovered = try SegmentStore(events: [Tapped.self], directory: .init(directory)).takeRecoveredRecords()
        } catch {
            check(false, "recovery threw \(error)")
            return
        }
        // No recovered record may come from a frame whose checksum fails: each is one of the
        // model's intact frames, in order.
        check(recovered.count <= model.records.count, "recovered \(recovered.count) records from \(model.records.count) intact frames")
        guard !collision else { return }
        check(recovered.count == expected.count, "recovered \(recovered.count) records, model \(expected.count)")
        for (record, expectation) in zip(recovered, expected) {
            check(record.event as? Tapped == expectation.event, "recovered \(record.event), model \(expectation.event)")
            check(record.isRedelivered == expectation.isRedelivered, "redelivered \(record.isRedelivered), model \(expectation.isRedelivered)")
            let index = UInt32(truncatingIfNeeded: record.deliveryTag?.position ?? .max)
            check(index == model.records[expectation.frame].index, "position \(index) for frame \(expectation.frame)")
        }

        let size = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int
        if model.isNewerVersion {
            check(recovered.isEmpty, "recovered \(recovered.count) records from a newer version's segment")
            check(FileManager.default.contents(atPath: path) == Data(bytes), "a newer version's segment was changed")
        } else if expected.isEmpty {
            check(size == nil, "a segment with nothing to deliver was kept, \(size ?? 0) bytes")
        } else {
            check(size == model.validByteCount, "segment cut to \(size ?? -1) bytes, model \(model.validByteCount)")
        }
    }
}
