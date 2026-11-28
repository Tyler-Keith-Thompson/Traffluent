// What the CBOR package's encoder and a store write, read back by an independent CBOR decoder
// (SwiftCBOR), so a mistake in the encoding can't hide behind the same mistake in the package's
// decoder. Both modules name a type CBOR: SwiftCBOR's is always written SwiftCBOR.CBOR here, and
// CBOREncoder is the package's alone.

import AsyncQueues
import CBOR
import Checksums
import Events
import Foundation
import Instrumentation
import Persistence
import PropertyBased
import SwiftCBOR
import SystemPackage
import Testing

@Suite("Records: read by another CBOR decoder", .timeLimit(.minutes(1)))
struct IndependentCBORTests {
    struct Tapped: Event {
        var number: Int
        var coupon: String?
    }

    @Test("An event's bytes are the CBOR map another decoder reads, keyed by text strings")
    func map() throws {
        let expected: SwiftCBOR.CBOR = .map([.utf8String("number"): .negativeInt(2), .utf8String("coupon"): .utf8String("SPRING")])

        let bytes = try CBOREncoder().encode(Tapped(number: -3, coupon: "SPRING"))
        let actual = try SwiftCBOR.CBOR.decode(bytes)

        #expect(actual == expected)
    }

    @Test("An optional's nil is left out of the map")
    func nilLeftOut() throws {
        let expected: SwiftCBOR.CBOR = .map([.utf8String("number"): .unsignedInt(4)])

        let bytes = try CBOREncoder().encode(Tapped(number: 4, coupon: nil))
        let actual = try SwiftCBOR.CBOR.decode(bytes)

        #expect(actual == expected)
    }

    @Test("A record a store keeps is the CBOR map another decoder reads: its identifier, timestamp, name, version, call site and event")
    func persistedRecord() throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("IndependentCBORTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let sut = try SegmentStore(events: [Tapped.self], directory: directory)
        let location = Events.SourceLocation(file: "/src/App/View.swift", fileID: "App/View.swift", function: "body", line: 12, column: 5)
        let record = EventRecord(event: Tapped(number: 7, coupon: nil), timestamp: Date(timeIntervalSinceReferenceDate: 2.5), sourceLocation: location)
        let expected: SwiftCBOR.CBOR = .map([
            .utf8String("id"): .utf8String(record.id.uuidString),
            .utf8String("timestamp"): .double(2.5),
            .utf8String("name"): .utf8String("Tapped"),
            .utf8String("version"): .unsignedInt(1),
            .utf8String("sourceLocation"): .map([
                .utf8String("fileID"): .utf8String("App/View.swift"),
                .utf8String("file"): .utf8String("/src/App/View.swift"),
                .utf8String("function"): .utf8String("body"),
                .utf8String("line"): .unsignedInt(12),
                .utf8String("column"): .unsignedInt(5),
            ]),
            .utf8String("event"): .map([.utf8String("number"): .unsignedInt(7)]),
        ])

        _ = sut.append(record)
        let name = try #require(try FileManager.default.contentsOfDirectory(atPath: directory.string).first)
        let bytes = try #require(FileManager.default.contents(atPath: directory.appending(name).string)).map { $0 }
        // The segment's 8-byte header, the frame's length and checksum, then the payload's kind byte.
        let payload = Array(bytes[17...])
        let actual = try SwiftCBOR.CBOR.decode(payload)

        #expect(actual == expected)
    }

    @Test("A record's session is the text string of its SessionKey under session, beside its other fields")
    func persistedSession() throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("IndependentCBORTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let sut = try SegmentStore(events: [Tapped.self], directory: directory)
        let session = UUID(uuidString: "019A2B3C-4D5E-7F60-8172-839405A6B7C8")!
        var context = ServiceContext.topLevel
        context[SessionKey.self] = session
        let record = EventRecord(event: Tapped(number: 7, coupon: nil), timestamp: Date(timeIntervalSinceReferenceDate: 2.5), sourceLocation: nil, context: context)
        let expected: SwiftCBOR.CBOR = .map([
            .utf8String("id"): .utf8String(record.id.uuidString),
            .utf8String("timestamp"): .double(2.5),
            .utf8String("name"): .utf8String("Tapped"),
            .utf8String("version"): .unsignedInt(1),
            .utf8String("session"): .utf8String("019A2B3C-4D5E-7F60-8172-839405A6B7C8"),
            .utf8String("event"): .map([.utf8String("number"): .unsignedInt(7)]),
        ])

        _ = sut.append(record)

        let name = try #require(try FileManager.default.contentsOfDirectory(atPath: directory.string).first)
        let bytes = try #require(FileManager.default.contents(atPath: directory.appending(name).string)).map { $0 }
        // The segment's 8-byte header, the frame's length and checksum, then the payload's kind byte.
        let actual = try SwiftCBOR.CBOR.decode(Array(bytes[17...]))
        #expect(actual == expected)
    }

    @Test("A record map written by another encoder comes back with the session under session, in any case, or with none when the key is missing, as a store wrote before it kept sessions", arguments: [
        ("019A2B3C-4D5E-7F60-8172-839405A6B7C8", "019A2B3C-4D5E-7F60-8172-839405A6B7C8"),
        ("019a2b3c-4d5e-7f60-8172-839405a6b7c8", "019A2B3C-4D5E-7F60-8172-839405A6B7C8"),
        (nil, nil),
    ] as [(String?, String?)])
    func sessionReadFromAnotherEncoder(written: String?, expected: String?) throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("IndependentCBORTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let id = UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!
        var fields: [SwiftCBOR.CBOR: SwiftCBOR.CBOR] = [
            .utf8String("id"): .utf8String(id.uuidString),
            .utf8String("timestamp"): .double(2.5),
            .utf8String("name"): .utf8String("Tapped"),
            .utf8String("version"): .unsignedInt(1),
            .utf8String("event"): .map([.utf8String("number"): .unsignedInt(7)]),
        ]
        fields[.utf8String("session")] = written.map(SwiftCBOR.CBOR.utf8String)
        let payload: [UInt8] = [0] + SwiftCBOR.CBOR.map(fields).encode()
        let checksum = payload.withUnsafeBytes { CRC32.checksum(of: $0) }
        let segment: [UInt8] = [0x54, 0x52, 0x46, 0x4C, 3, 0, 0, 0]
            + withUnsafeBytes(of: UInt32(payload.count).littleEndian) { Array($0) }
            + withUnsafeBytes(of: checksum.littleEndian) { Array($0) }
            + payload
        try FileManager.default.createDirectory(atPath: directory.string, withIntermediateDirectories: true)
        try #require(FileManager.default.createFile(atPath: directory.appending("00000000000000000001.segment").string, contents: Data(segment)))

        let recovered = try SegmentStore(events: [Tapped.self], directory: directory).takeRecoveredRecords()

        let actual = try #require(recovered.first)
        #expect(recovered.count == 1)
        #expect(actual.id == id)
        #expect(actual.context[SessionKey.self] == expected.flatMap(UUID.init(uuidString:)))
    }

    @Test("A record whose session isn't a UUID string, null included, is dropped as undecodable, not recovered without it", arguments: ["null", "an integer", "text that isn't a UUID", "a map", "16 bytes"])
    func malformedSessionUndecodable(kind: String) async throws {
        // SwiftCBOR's values aren't Sendable, so a test argument names one.
        let sessions: [String: SwiftCBOR.CBOR] = [
            "null": .null,
            "an integer": .unsignedInt(7),
            "text that isn't a UUID": .utf8String("not-a-uuid"),
            "a map": .map([:]),
            "16 bytes": .byteString(Array(repeating: 1, count: 16)),
        ]
        let session = try #require(sessions[kind])
        let directory = FilePath(NSTemporaryDirectory()).appending("IndependentCBORTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let payload: [UInt8] = [0] + SwiftCBOR.CBOR.map([
            .utf8String("id"): .utf8String("6F9619FF-8B86-D011-B42D-00C04FC964FF"),
            .utf8String("timestamp"): .double(2.5),
            .utf8String("name"): .utf8String("Tapped"),
            .utf8String("version"): .unsignedInt(1),
            .utf8String("session"): session,
            .utf8String("event"): .map([.utf8String("number"): .unsignedInt(7)]),
        ]).encode()
        let checksum = payload.withUnsafeBytes { CRC32.checksum(of: $0) }
        let segment: [UInt8] = [0x54, 0x52, 0x46, 0x4C, 3, 0, 0, 0]
            + withUnsafeBytes(of: UInt32(payload.count).littleEndian) { Array($0) }
            + withUnsafeBytes(of: checksum.littleEndian) { Array($0) }
            + payload
        try FileManager.default.createDirectory(atPath: directory.string, withIntermediateDirectories: true)
        try #require(FileManager.default.createFile(atPath: directory.appending("00000000000000000001.segment").string, contents: Data(segment)))
        let expected = [DropReport.undecodable(recordCount: 1)]

        // Counted rather than kept: a recovered record's tag would keep the store alive.
        let recoveredCount: Int
        let reports: AsyncQueue<DropReport>
        do {
            let sut = try SegmentStore(events: [Tapped.self], directory: directory)
            recoveredCount = sut.takeRecoveredRecords().count
            reports = sut.dropReports
        }

        // The store is gone, so its reports have ended.
        var actual: [DropReport] = []
        for await report in reports {
            actual.append(report)
        }
        #expect(recoveredCount == 0)
        #expect(actual == expected)
    }

    @Test("A record's timestamp is the double of its seconds since 2001 that the Date stores, so it reads back exactly")
    func timestampExact() throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("IndependentCBORTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        // 0.1 s past the reference date: its seconds since 1970 as a double round away its last bit.
        let expected = Date(timeIntervalSinceReferenceDate: 0.1)
        let store = try SegmentStore(events: [Tapped.self], directory: directory)
        _ = store.append(EventRecord(event: Tapped(number: 1, coupon: nil), timestamp: expected, sourceLocation: nil))
        let bytes = try #require(FileManager.default.contents(atPath: directory.appending("00000000000000000001.segment").string)).map { $0 }
        let sut = try SegmentStore(events: [Tapped.self], directory: directory)

        let written = try SwiftCBOR.CBOR.decode(Array(bytes[17...]))
        let actual = sut.takeRecoveredRecords().map(\.timestamp)

        guard case .map(let map)? = written else {
            Issue.record("Not a map: \(String(describing: written))")
            return
        }
        #expect(map[.utf8String("timestamp")] == .double(0.1))
        #expect(actual == [expected])
    }

    @Test("A record with no call site leaves sourceLocation out, and one whose file is its file ID leaves the file out")
    func recordWithoutCallSite() throws {
        let withoutCallSite = FilePath(NSTemporaryDirectory()).appending("IndependentCBORTests-\(UUID().uuidString)")
        let withFileID = FilePath(NSTemporaryDirectory()).appending("IndependentCBORTests-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(atPath: withoutCallSite.string)
            try? FileManager.default.removeItem(atPath: withFileID.string)
        }
        let location = Events.SourceLocation(file: "App/View.swift", fileID: "App/View.swift", function: "body", line: 1, column: 1)
        let expectedRecordKeys: Set<SwiftCBOR.CBOR> = [.utf8String("id"), .utf8String("timestamp"), .utf8String("name"), .utf8String("version"), .utf8String("event")]
        let expectedLocationKeys: Set<SwiftCBOR.CBOR> = [.utf8String("fileID"), .utf8String("function"), .utf8String("line"), .utf8String("column")]

        _ = try SegmentStore(events: [Tapped.self], directory: withoutCallSite)
            .append(EventRecord(event: Tapped(number: 1, coupon: nil), timestamp: Date(timeIntervalSinceReferenceDate: 0), sourceLocation: nil))
        _ = try SegmentStore(events: [Tapped.self], directory: withFileID)
            .append(EventRecord(event: Tapped(number: 2, coupon: nil), timestamp: Date(timeIntervalSinceReferenceDate: 0), sourceLocation: location))
        let first = try #require(FileManager.default.contents(atPath: withoutCallSite.appending("00000000000000000001.segment").string)).map { $0 }
        let second = try #require(FileManager.default.contents(atPath: withFileID.appending("00000000000000000001.segment").string)).map { $0 }
        // Past the segment's 8-byte header, the frame's length and checksum and the payload's kind.
        let firstRecord = try SwiftCBOR.CBOR.decode(Array(first[17...]))
        let secondRecord = try SwiftCBOR.CBOR.decode(Array(second[17...]))

        guard case .map(let firstMap)? = firstRecord, case .map(let secondMap)? = secondRecord, case .map(let secondLocation)? = secondMap[.utf8String("sourceLocation")] else {
            Issue.record("Not maps: \(String(describing: firstRecord)), \(String(describing: secondRecord))")
            return
        }
        #expect(Set(firstMap.keys) == expectedRecordKeys)
        #expect(Set(secondLocation.keys) == expectedLocationKeys)
    }

    @Test("Any integer is the CBOR integer another decoder reads", .tags(.randomized))
    func integers() async {
        await propertyCheck(count: 300, input: Gen.int64(in: .min ... .max)) { value in
            let expected: SwiftCBOR.CBOR = value < 0 ? .negativeInt(UInt64(-(value + 1))) : .unsignedInt(UInt64(value))

            let bytes = try? CBOREncoder().encode(value)
            let actual = try? bytes.flatMap { try SwiftCBOR.CBOR.decode($0) }

            #expect(actual == expected)
        }
    }
}

extension IndependentCBORTests.Tapped: Codable {}
