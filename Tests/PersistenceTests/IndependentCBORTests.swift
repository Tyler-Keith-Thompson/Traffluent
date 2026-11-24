// What BinaryCodable and a store write, read back by an independent CBOR decoder (SwiftCBOR), so a
// mistake in the encoding can't hide behind the same mistake in this library's decoder.

import Events
import Foundation
import Persistence
import PropertyBased
import SwiftCBOR
import SystemPackage
import Testing

@Suite("BinaryCodable: read by another CBOR decoder", .timeLimit(.minutes(1)))
struct IndependentCBORTests {
    struct Tapped: Event {
        var number: Int
        var coupon: String?
    }

    @Test("Every standard type's bytes are the CBOR value another decoder reads")
    func standardTypes() throws {
        let uuid = UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!
        let uuidBytes: [UInt8] = [0xE6, 0x21, 0xE1, 0xF8, 0xC3, 0x6C, 0x49, 0x5A, 0x93, 0xFC, 0x0C, 0x24, 0x7A, 0x3E, 0x6E, 0x5F]
        let nestedNone: Int?? = .some(.none)
        let expected: [CBOR] = [
            .unsignedInt(0), .unsignedInt(UInt64.max), .negativeInt(0), .negativeInt(UInt64(Int64.max)),
            .unsignedInt(255), .negativeInt(99), .boolean(true), .boolean(false), .double(-0.1), .float(3.5),
            .utf8String("שלום"), .array([.unsignedInt(1), .unsignedInt(2)]), .null, .array([.null]),
            .double(1.5), .tagged(CBOR.Tag(rawValue: 37), .byteString(uuidBytes)), .undefined,
        ]
        var encoder = BinaryEncoder()
        encoder.encode(UInt64(0))
        encoder.encode(UInt64.max)
        encoder.encode(-1)
        encoder.encode(Int64.min)
        encoder.encode(UInt8(255))
        encoder.encode(Int8(-100))
        encoder.encode(true)
        encoder.encode(false)
        encoder.encode(-0.1)
        encoder.encode(Float(3.5))
        encoder.encode("שלום")
        encoder.encode([1, 2])
        encoder.encode(String?.none)
        encoder.encode(nestedNone)
        encoder.encode(Date(timeIntervalSinceReferenceDate: 1.5))
        encoder.encode(uuid)
        encoder.encode(Sensitive("ada@example.com"))
        let sut = CBORDecoder(input: encoder.bytes)

        let actual = try expected.map { _ in try sut.decodeItem() ?? .break }

        #expect(actual == expected)
    }

    @Test("A map's bytes are the CBOR map another decoder reads, keyed by text strings")
    func map() throws {
        let expected: CBOR = .map([.utf8String("number"): .negativeInt(2), .utf8String("coupon"): .utf8String("SPRING")])
        var encoder = BinaryEncoder()

        Tapped(number: -3, coupon: "SPRING").encode(to: &encoder)
        let actual = try CBOR.decode(encoder.bytes)

        #expect(actual == expected)
    }

    @Test("A record a store keeps is the CBOR map another decoder reads: its identifier, timestamp, name, call site and event")
    func persistedRecord() throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("IndependentCBORTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let sut = try SegmentStore(events: [Tapped.self], directory: directory)
        let location = Events.SourceLocation(file: "/src/App/View.swift", fileID: "App/View.swift", function: "body", line: 12, column: 5)
        let record = EventRecord(event: Tapped(number: 7, coupon: nil), timestamp: Date(timeIntervalSinceReferenceDate: 2.5), sourceLocation: location)
        let identifier = withUnsafeBytes(of: record.id.uuid) { Array($0) }
        let expected: CBOR = .map([
            .utf8String("id"): .tagged(CBOR.Tag(rawValue: 37), .byteString(identifier)),
            .utf8String("timestamp"): .double(2.5),
            .utf8String("name"): .utf8String("Tapped"),
            .utf8String("sourceLocation"): .map([
                .utf8String("fileID"): .utf8String("App/View.swift"),
                .utf8String("file"): .utf8String("/src/App/View.swift"),
                .utf8String("function"): .utf8String("body"),
                .utf8String("line"): .unsignedInt(12),
                .utf8String("column"): .unsignedInt(5),
            ]),
            .utf8String("event"): .map([.utf8String("number"): .unsignedInt(7), .utf8String("coupon"): .null]),
        ])

        _ = sut.append(record)
        let name = try #require(try FileManager.default.contentsOfDirectory(atPath: directory.string).first)
        let bytes = try #require(FileManager.default.contents(atPath: directory.appending(name).string)).map { $0 }
        // The segment's 8-byte header, the frame's length and checksum, then the payload's kind byte.
        let payload = Array(bytes[17...])
        let actual = try CBOR.decode(payload)

        #expect(actual == expected)
    }

    @Test("A record with no call site writes its sourceLocation as null, and one whose file is its file ID writes the file as null")
    func recordWithoutCallSite() throws {
        let withoutCallSite = FilePath(NSTemporaryDirectory()).appending("IndependentCBORTests-\(UUID().uuidString)")
        let withFileID = FilePath(NSTemporaryDirectory()).appending("IndependentCBORTests-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(atPath: withoutCallSite.string)
            try? FileManager.default.removeItem(atPath: withFileID.string)
        }
        let location = Events.SourceLocation(file: "App/View.swift", fileID: "App/View.swift", function: "body", line: 1, column: 1)
        let expectedRecordKeys: Set<CBOR> = [.utf8String("id"), .utf8String("timestamp"), .utf8String("name"), .utf8String("sourceLocation"), .utf8String("event")]
        let expectedLocationKeys: Set<CBOR> = [.utf8String("fileID"), .utf8String("file"), .utf8String("function"), .utf8String("line"), .utf8String("column")]

        _ = try SegmentStore(events: [Tapped.self], directory: withoutCallSite)
            .append(EventRecord(event: Tapped(number: 1, coupon: nil), timestamp: Date(timeIntervalSinceReferenceDate: 0), sourceLocation: nil))
        _ = try SegmentStore(events: [Tapped.self], directory: withFileID)
            .append(EventRecord(event: Tapped(number: 2, coupon: nil), timestamp: Date(timeIntervalSinceReferenceDate: 0), sourceLocation: location))
        let first = try #require(FileManager.default.contents(atPath: withoutCallSite.appending("00000000000000000001.segment").string)).map { $0 }
        let second = try #require(FileManager.default.contents(atPath: withFileID.appending("00000000000000000001.segment").string)).map { $0 }
        // Past the segment's 8-byte header, the frame's length and checksum and the payload's kind.
        let firstRecord = try CBOR.decode(Array(first[17...]))
        let secondRecord = try CBOR.decode(Array(second[17...]))

        guard case .map(let firstMap)? = firstRecord, case .map(let secondMap)? = secondRecord, case .map(let secondLocation)? = secondMap[.utf8String("sourceLocation")] else {
            Issue.record("Not maps: \(String(describing: firstRecord)), \(String(describing: secondRecord))")
            return
        }
        #expect(Set(firstMap.keys) == expectedRecordKeys)
        #expect(firstMap[.utf8String("sourceLocation")] == .null)
        #expect(Set(secondLocation.keys) == expectedLocationKeys)
        #expect(secondLocation[.utf8String("file")] == .null)
    }

    @Test("Any integer is the CBOR integer another decoder reads", .tags(.randomized))
    func integers() async {
        await propertyCheck(count: 300, input: Gen.int64(in: .min ... .max)) { value in
            let expected: CBOR = value < 0 ? .negativeInt(UInt64(-(value + 1))) : .unsignedInt(UInt64(value))
            var encoder = BinaryEncoder()

            encoder.encode(value)
            let actual = try? CBOR.decode(encoder.bytes)

            #expect(actual == expected)
        }
    }
}

extension IndependentCBORTests.Tapped: BinaryCodable {
    func encode(to encoder: inout BinaryEncoder) {
        encoder.encodeMap { map in
            map.encode(number, forKey: "number")
            map.encode(coupon, forKey: "coupon")
        }
    }

    init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
        var map = try decoder.decodeMap()
        number = try map.decode(forKey: "number")
        coupon = try map.decode(forKey: "coupon")
    }
}
