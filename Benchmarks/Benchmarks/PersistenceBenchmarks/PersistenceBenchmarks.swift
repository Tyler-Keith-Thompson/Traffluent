import Benchmark
import Checksums
import Events
import Foundation
import Persistence
import Trackers

struct Tapped: Event {
    var number: Int
    var screen: String
}

// Swift's synthesized conformance, as an app's own event type has.
extension Tapped: Codable {}

// A record as the positional encoding the keyed one replaced wrote it, by hand with no library
// code: its identifier's 16 bytes, timestamp, fileID, file (nil: it equals fileID), function, line,
// column and event name, then the event's number and screen, one after another with no names or
// type tags (little-endian 64-bit numbers, a string as its UTF-8 count as a UInt32 then its bytes,
// an optional as a byte before the value). These baselines are the floor the store's append
// and recovery are measured against, with no ratio budget: the store does work they leave out
// (directory listing, event-type registration, more allocations per record), so their ratio
// measures the store as much as the encoding. The encoding's own budget, D9 in
// .kanban/triage.md, is measured in EventMacrosBenchmarks.
struct PositionalRecord {
    var id: UUID
    var timestamp: Date
    var fileID: String
    var function: String
    var line: Int
    var column: Int
    var name: String
    var number: Int
    var screen: String

    func encode(to bytes: inout [UInt8]) {
        Swift.withUnsafeBytes(of: id.uuid) { bytes.append(contentsOf: $0) }
        bytes.appendLittleEndian(timestamp.timeIntervalSinceReferenceDate.bitPattern)
        bytes.appendCounted(fileID)
        bytes.append(0)
        bytes.appendCounted(function)
        bytes.appendLittleEndian(UInt64(bitPattern: Int64(line)))
        bytes.appendLittleEndian(UInt64(bitPattern: Int64(column)))
        bytes.appendCounted(name)
        bytes.appendLittleEndian(UInt64(bitPattern: Int64(number)))
        bytes.appendCounted(screen)
    }

    init(id: UUID, timestamp: Date, fileID: String, function: String, line: Int, column: Int, name: String, number: Int, screen: String) {
        self.id = id
        self.timestamp = timestamp
        self.fileID = fileID
        self.function = function
        self.line = line
        self.column = column
        self.name = name
        self.number = number
        self.screen = screen
    }

    init(from reader: inout PositionalReader) throws(PositionalReader.Failure) {
        let idBytes = try reader.read(16)
        var uuid: uuid_t = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        withUnsafeMutableBytes(of: &uuid) { $0.copyBytes(from: idBytes) }
        id = UUID(uuid: uuid)
        timestamp = Date(timeIntervalSinceReferenceDate: Double(bitPattern: try reader.readUInt64()))
        fileID = try reader.readString()
        _ = try reader.read(1)
        function = try reader.readString()
        line = Int(Int64(bitPattern: try reader.readUInt64()))
        column = Int(Int64(bitPattern: try reader.readUInt64()))
        name = try reader.readString()
        number = Int(Int64(bitPattern: try reader.readUInt64()))
        screen = try reader.readString()
    }
}

extension [UInt8] {
    fileprivate mutating func appendLittleEndian(_ value: UInt64) {
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

/// Reads `PositionalRecord`'s fields, checking each against the bytes left, as a decoder must.
struct PositionalReader {
    struct Failure: Error {}

    let bytes: [UInt8]
    var position = 0

    mutating func read(_ count: Int) throws(Failure) -> ArraySlice<UInt8> {
        guard bytes.count - position >= count else { throw Failure() }
        defer { position += count }
        return bytes[position ..< position + count]
    }

    mutating func readUInt64() throws(Failure) -> UInt64 {
        guard bytes.count - position >= 8 else { throw Failure() }
        defer { position += 8 }
        let start = position
        return bytes.withUnsafeBytes { UInt64(littleEndian: $0.loadUnaligned(fromByteOffset: start, as: UInt64.self)) }
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

/// A segment frame as the store writes one: the payload's length and CRC-32, little-endian
/// `UInt32`s, then the payload, a record's kind byte (0) and its positional bytes.
func positionalFrame(of record: PositionalRecord) -> [UInt8] {
    var frame: [UInt8] = [0, 0, 0, 0, 0, 0, 0, 0, 0]
    record.encode(to: &frame)
    let length = UInt32(frame.count - 8)
    let checksum = frame.withUnsafeBytes { CRC32.checksum(of: UnsafeRawBufferPointer(rebasing: $0[8...])) }
    frame.withUnsafeMutableBytes { raw in
        raw.storeBytes(of: length.littleEndian, toByteOffset: 0, as: UInt32.self)
        raw.storeBytes(of: checksum.littleEndian, toByteOffset: 4, as: UInt32.self)
    }
    return frame
}

/// The positional records in a segment file's `bytes`, after its 8-byte header, each frame's
/// CRC-32 checked as the store checks it.
func positionalRecords(in bytes: [UInt8]) throws(PositionalReader.Failure) -> [PositionalRecord] {
    var records: [PositionalRecord] = []
    var offset = 8
    while bytes.count - offset >= 8 {
        let start = offset
        let (length, checksum) = bytes.withUnsafeBytes { raw in
            (Int(UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: start, as: UInt32.self))),
             UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: start + 4, as: UInt32.self)))
        }
        let payload = start + 8 ..< start + 8 + length
        guard length >= 1, payload.upperBound <= bytes.count else { throw PositionalReader.Failure() }
        guard bytes.withUnsafeBytes({ CRC32.checksum(of: UnsafeRawBufferPointer(rebasing: $0[payload])) }) == checksum else { throw PositionalReader.Failure() }
        // Read in place, past the kind byte, as the store's decoder reads a slice of the file.
        var reader = PositionalReader(bytes: bytes, position: payload.lowerBound + 1)
        records.append(try PositionalRecord(from: &reader))
        offset = payload.upperBound
    }
    return records
}

/// The whole file at `path`, read as the store reads a segment: opened, then read to its end.
func readFile(atPath path: String) -> [UInt8] {
    let descriptor = open(path, O_RDONLY)
    defer { close(descriptor) }
    var bytes: [UInt8] = []
    var chunk = [UInt8](repeating: 0, count: 64 * 1024)
    while true {
        let count = chunk.withUnsafeMutableBytes { read(descriptor, $0.baseAddress, $0.count) }
        guard count > 0 else { return bytes }
        bytes.append(contentsOf: chunk[..<count])
    }
}

let benchmarks: @Sendable () -> Void = {
    Benchmark.defaultConfiguration.metrics = [.wallClock, .mallocCountTotal]
    Benchmark.defaultConfiguration.maxDuration = .seconds(2)

    let tracks = 1_000
    // About the size of a tracked Tapped record's frame.
    let frame = [UInt8](repeating: 0x2A, count: 112)

    let location = SourceLocation(file: "App/CheckoutView.swift", fileID: "App/CheckoutView.swift", function: "body", line: 42, column: 13)
    // Built before each window, so only the coding and the store's own work are measured.
    let records = (0 ..< tracks).map { EventRecord(event: Tapped(number: $0, screen: "Checkout"), timestamp: Date(timeIntervalSinceReferenceDate: Double($0)), sourceLocation: location) }
    let positional = records.map {
        PositionalRecord(id: $0.id, timestamp: $0.timestamp, fileID: location.fileID, function: location.function, line: location.line, column: location.column, name: Tapped.name, number: ($0.event as! Tapped).number, screen: "Checkout")
    }
    // The segment header, version 3, which a store's segment starts with.
    let header: [UInt8] = [0x54, 0x52, 0x46, 0x4C, 3, 0, 0, 0]

    // MARK: record: a thousand records' encoding, written to and recovered from a store.
    //
    // Each BASELINE pairs with the SegmentStore benchmark after it, doing the same framing,
    // CRC-32 and file I/O with the positional encoding, so the two differ only in the encoding
    // (and the store's own bookkeeping).

    // Each record is encoded positionally, framed with its CRC-32 and written with one write().
    Benchmark("record append: BASELINE positional encoding", configuration: .init(scalingFactor: .kilo)) { benchmark in
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let descriptor = open(directory + "/positional", O_WRONLY | O_CREAT | O_APPEND, 0o600)
        defer { close(descriptor) }
        _ = header.withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }
        benchmark.startMeasurement()
        for record in positional {
            let frame = positionalFrame(of: record)
            blackHole(frame.withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) })
        }
        benchmark.stopMeasurement()
    }

    // The segment file is read whole, each frame's CRC-32 checked and each record decoded.
    Benchmark("record recovery: BASELINE positional encoding", configuration: .init(scalingFactor: .kilo)) { benchmark in
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let path = directory + "/positional"
        do {
            let descriptor = open(path, O_WRONLY | O_CREAT | O_APPEND, 0o600)
            defer { close(descriptor) }
            _ = header.withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }
            for record in positional {
                _ = positionalFrame(of: record).withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }
            }
        }
        benchmark.startMeasurement()
        blackHole(try positionalRecords(in: readFile(atPath: path)))
        benchmark.stopMeasurement()
    }

    // Each record is encoded, framed with its CRC-32 and written with one write().
    Benchmark("record: SegmentStore append", configuration: .init(scalingFactor: .kilo)) { benchmark in
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let store = try SegmentStore(events: [Tapped.self], directory: .init(directory))
        benchmark.startMeasurement()
        for record in records {
            blackHole(store.append(record))
        }
        benchmark.stopMeasurement()
    }

    // Opening a store reads its segments, checks each frame's CRC-32 and decodes each record.
    Benchmark("record: SegmentStore recovery", configuration: .init(scalingFactor: .kilo)) { benchmark in
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(atPath: directory) }
        do {
            // Closed before the store under measurement opens: one store per directory at a time.
            let earlier = try SegmentStore(events: [Tapped.self], directory: .init(directory))
            for record in records {
                _ = earlier.append(record)
            }
        }
        benchmark.startMeasurement()
        let store = try SegmentStore(events: [Tapped.self], directory: .init(directory))
        blackHole(store.takeRecoveredRecords())
        benchmark.stopMeasurement()
    }

    // MARK: track: the cost of one tracked event, written through to disk.
    //
    // `track` only queues the event, and the tracker's worker writes it, so these measure what the
    // caller pays. The worker runs on a dispatch queue, which the simulated counts don't see; judge
    // its cost by wall clock (`just bench`).

    // The hand-written form the library must keep pace with: one write() of a record-sized frame
    // to a file opened for appending, per event.
    Benchmark("track: BASELINE raw write()", configuration: .init(scalingFactor: .kilo)) { benchmark in
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let descriptor = open(directory + "/raw", O_WRONLY | O_CREAT | O_APPEND, 0o600)
        defer { close(descriptor) }
        benchmark.startMeasurement()
        for _ in 0 ..< tracks {
            blackHole(frame.withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) })
        }
        benchmark.stopMeasurement()
    }

    Benchmark("track: Tracker(store:) with a SegmentStore", configuration: .init(scalingFactor: .kilo)) { benchmark in
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let tracker = Tracker(store: try SegmentStore(events: [Tapped.self], directory: .init(directory)))
        benchmark.startMeasurement()
        for number in 0 ..< tracks {
            tracker.track(Tapped(number: number, screen: "Checkout"))
        }
        benchmark.stopMeasurement()
        await tracker.finish()
    }

    // The same tracking with no store: what a store adds to the caller's cost.
    Benchmark("track: Tracker() in memory only", configuration: .init(scalingFactor: .kilo)) { benchmark in
        let tracker = Tracker()
        benchmark.startMeasurement()
        for number in 0 ..< tracks {
            tracker.track(Tapped(number: number, screen: "Checkout"))
        }
        benchmark.stopMeasurement()
        await tracker.finish()
    }
}

/// A new, empty directory for one run's files.
func scratchDirectory() -> String {
    let path = NSTemporaryDirectory() + "PersistenceBenchmarks-" + UUID().uuidString
    try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    return path
}
