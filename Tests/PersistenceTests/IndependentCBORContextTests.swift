// The context members of a record map (TRAF-145), as a store writes them, read back by an
// independent CBOR decoder (SwiftCBOR), and maps another encoder wrote read back by a store, so a
// mistake in the encoding can't hide behind the same mistake in the package's decoder. Both
// modules name a type CBOR: SwiftCBOR's is always written SwiftCBOR.CBOR here.

import AsyncQueues
import Checksums
import Events
import Foundation
import Instrumentation
import Persistence
import StandardContext
import SwiftCBOR
import SystemPackage
import Testing

@Suite("Records: context members read by another CBOR decoder", .timeLimit(.minutes(1)))
struct IndependentCBORContextTests {
    struct Tapped: Event {
        var number: Int
    }

    @Test("A record's session is a member of its map, and its other kept context keys members of a map under context, each in its own form; its identifier for vendor is none")
    func persistedContext() throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("IndependentCBORContextTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let sut = try SegmentStore(events: [Tapped.self], directory: directory)
        var context = ServiceContext.topLevel
        context[SessionKey.self] = UUID(uuidString: "019A2B3C-4D5E-7F60-8172-839405A6B7C8")
        context[SampleRateKey.self] = try SampleRate(0.25)
        context[ScreenKey.self] = "Checkout"
        context[ApplicationKey.self] = ApplicationKey.Value(bundleIdentifier: "com.example.shop", version: "2.4.1", build: nil)
        context[DeviceKey.self] = DeviceKey.Value(model: "iPad16,3", formFactor: .pad)
        context[OperatingSystemKey.self] = OperatingSystemKey.Value(name: "iOS", version: "26.1.0")
        context[LocaleKey.self] = Locale(identifier: "fr_CA")
        context[NetworkKey.self] = .wiredEthernet
        context[VendorIdentifierKey.self] = Sensitive(UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!)
        let record = EventRecord(event: Tapped(number: 7), timestamp: Date(timeIntervalSinceReferenceDate: 2.5), sourceLocation: nil, context: context)
        let expected: SwiftCBOR.CBOR = .map([
            .utf8String("id"): .utf8String(record.id.uuidString),
            .utf8String("timestamp"): .double(2.5),
            .utf8String("name"): .utf8String("Tapped"),
            .utf8String("version"): .unsignedInt(1),
            .utf8String("session"): .utf8String("019A2B3C-4D5E-7F60-8172-839405A6B7C8"),
            .utf8String("context"): .map([
                .utf8String("sampleRate"): .double(0.25),
                .utf8String("screen"): .utf8String("Checkout"),
                .utf8String("application"): .map([
                    .utf8String("bundleIdentifier"): .utf8String("com.example.shop"),
                    .utf8String("version"): .utf8String("2.4.1"),
                ]),
                .utf8String("device"): .map([
                    .utf8String("model"): .utf8String("iPad16,3"),
                    .utf8String("formFactor"): .utf8String("pad"),
                ]),
                .utf8String("operatingSystem"): .map([
                    .utf8String("name"): .utf8String("iOS"),
                    .utf8String("version"): .utf8String("26.1.0"),
                ]),
                .utf8String("locale"): .utf8String("fr_CA"),
                .utf8String("network"): .utf8String("wiredEthernet"),
            ]),
            .utf8String("event"): .map([.utf8String("number"): .unsignedInt(7)]),
        ])

        _ = sut.append(record)

        let name = try #require(try FileManager.default.contentsOfDirectory(atPath: directory.string).first)
        let bytes = try #require(FileManager.default.contents(atPath: directory.appending(name).string)).map { $0 }
        // The segment's 8-byte header, the frame's length and checksum, then the payload's kind byte.
        let actual = try SwiftCBOR.CBOR.decode(Array(bytes[17...]))
        #expect(actual == expected)
    }

    @Test("Each form factor and network connection is written under its own name", arguments: [
        (DeviceKey.Value.FormFactor.phone, NetworkKey.Value.wifi, "phone", "wifi"),
        (.pad, .cellular, "pad", "cellular"),
        (.mac, .wiredEthernet, "mac", "wiredEthernet"),
        (.tv, .other, "tv", "other"),
        (.watch, .offline, "watch", "offline"),
        (.vision, .offline, "vision", "offline"),
    ])
    func persistedNames(formFactor: DeviceKey.Value.FormFactor, network: NetworkKey.Value, expectedFormFactor: String, expectedNetwork: String) throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("IndependentCBORContextTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let sut = try SegmentStore(events: [Tapped.self], directory: directory)
        var context = ServiceContext.topLevel
        context[DeviceKey.self] = DeviceKey.Value(model: "x", formFactor: formFactor)
        context[NetworkKey.self] = network

        _ = sut.append(EventRecord(event: Tapped(number: 1), timestamp: Date(timeIntervalSinceReferenceDate: 0), sourceLocation: nil, context: context))

        let bytes = try #require(FileManager.default.contents(atPath: directory.appending("00000000000000000001.segment").string)).map { $0 }
        let written = try SwiftCBOR.CBOR.decode(Array(bytes[17...]))
        guard case .map(let map)? = written, case .map(let members)? = map[.utf8String("context")], case .map(let device)? = members[.utf8String("device")] else {
            Issue.record("Not a map with a device: \(String(describing: written))")
            return
        }
        #expect(device[.utf8String("formFactor")] == .utf8String(expectedFormFactor))
        #expect(members[.utf8String("network")] == .utf8String(expectedNetwork))
    }

    @Test("A record map another encoder wrote comes back with each context member it holds as its key, skipping one of another name, or none when there is no context map, as a store wrote before it kept them", arguments: [true, false])
    func contextReadFromAnotherEncoder(withMembers: Bool) throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("IndependentCBORContextTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        var fields: [SwiftCBOR.CBOR: SwiftCBOR.CBOR] = [
            .utf8String("id"): .utf8String("6F9619FF-8B86-D011-B42D-00C04FC964FF"),
            .utf8String("timestamp"): .double(2.5),
            .utf8String("name"): .utf8String("Tapped"),
            .utf8String("version"): .unsignedInt(1),
            .utf8String("session"): .utf8String("019A2B3C-4D5E-7F60-8172-839405A6B7C8"),
            .utf8String("event"): .map([.utf8String("number"): .unsignedInt(7)]),
        ]
        if withMembers {
            // A member of another name, as a later release might add, is skipped.
            fields[.utf8String("context")] = .map([
                .utf8String("sampleRate"): .double(0.5),
                .utf8String("screen"): .utf8String("Cart"),
                .utf8String("application"): .map([.utf8String("build"): .utf8String("418")]),
                .utf8String("device"): .map([.utf8String("model"): .utf8String("AppleTV14,1"), .utf8String("formFactor"): .utf8String("tv")]),
                .utf8String("operatingSystem"): .map([.utf8String("name"): .utf8String("tvOS"), .utf8String("version"): .utf8String("26.0.0")]),
                .utf8String("locale"): .utf8String("ja_JP"),
                .utf8String("network"): .utf8String("offline"),
                .utf8String("region"): .utf8String("eu-west"),
            ])
        }
        let payload: [UInt8] = [0] + SwiftCBOR.CBOR.map(fields).encode()
        let checksum = payload.withUnsafeBytes { CRC32.checksum(of: $0) }
        let segment: [UInt8] = [0x54, 0x52, 0x46, 0x4C, 3, 0, 0, 0]
            + withUnsafeBytes(of: UInt32(payload.count).littleEndian) { Array($0) }
            + withUnsafeBytes(of: checksum.littleEndian) { Array($0) }
            + payload
        try FileManager.default.createDirectory(atPath: directory.string, withIntermediateDirectories: true)
        try #require(FileManager.default.createFile(atPath: directory.appending("00000000000000000001.segment").string, contents: Data(segment)))
        let expectedRate = withMembers ? try SampleRate(0.5) : nil
        let expectedScreen = withMembers ? "Cart" : nil
        let expectedApplication = withMembers ? ApplicationKey.Value(bundleIdentifier: nil, version: nil, build: "418") : nil
        let expectedDevice = withMembers ? DeviceKey.Value(model: "AppleTV14,1", formFactor: .tv) : nil
        let expectedSystem = withMembers ? OperatingSystemKey.Value(name: "tvOS", version: "26.0.0") : nil
        let expectedLocale = withMembers ? Locale(identifier: "ja_JP") : nil
        let expectedNetwork: NetworkKey.Value? = withMembers ? .offline : nil
        let expectedCount = withMembers ? 8 : 1

        let recovered = try SegmentStore(events: [Tapped.self], directory: directory).takeRecoveredRecords()

        let actual = try #require(recovered.first)
        #expect(recovered.count == 1)
        #expect(actual.context[SessionKey.self] == UUID(uuidString: "019A2B3C-4D5E-7F60-8172-839405A6B7C8"))
        #expect(actual.context[SampleRateKey.self] == expectedRate)
        #expect(actual.context[ScreenKey.self] == expectedScreen)
        #expect(actual.context[ApplicationKey.self] == expectedApplication)
        #expect(actual.context[DeviceKey.self] == expectedDevice)
        #expect(actual.context[OperatingSystemKey.self] == expectedSystem)
        #expect(actual.context[LocaleKey.self] == expectedLocale)
        #expect(actual.context[NetworkKey.self] == expectedNetwork)
        #expect(actual.context.count == expectedCount)
    }

    @Test("A record whose context map, or a member of it, holds anything but its form, null included, is dropped as undecodable, not recovered without it", arguments: [
        "context null", "context text", "context array",
        "sampleRate null", "sampleRate below 0", "sampleRate above 1", "sampleRate NaN", "sampleRate text", "sampleRate integer",
        "screen null", "screen integer",
        "application null", "application text", "application version null", "application build integer",
        "device null", "device without model", "device without formFactor", "device formFactor null", "device formFactor integer",
        "operatingSystem null", "operatingSystem without version", "operatingSystem name integer",
        "locale null", "locale integer",
        "network null", "network integer",
    ])
    func malformedMemberUndecodable(kind: String) async throws {
        // SwiftCBOR's values aren't Sendable, so a test argument names one.
        let members: [String: (String, SwiftCBOR.CBOR)] = [
            "context null": ("context", .null),
            "context text": ("context", .utf8String("Checkout")),
            "context array": ("context", .array([.utf8String("Checkout")])),
            "sampleRate null": ("sampleRate", .null),
            "sampleRate below 0": ("sampleRate", .double(-Double.leastNonzeroMagnitude)),
            "sampleRate above 1": ("sampleRate", .double(1.0.nextUp)),
            "sampleRate NaN": ("sampleRate", .double(.nan)),
            "sampleRate text": ("sampleRate", .utf8String("0.5")),
            // A rate is a double, as the store writes it: an integer, even 1, is another form.
            "sampleRate integer": ("sampleRate", .unsignedInt(1)),
            "screen null": ("screen", .null),
            "screen integer": ("screen", .unsignedInt(3)),
            "application null": ("application", .null),
            "application text": ("application", .utf8String("com.example.shop")),
            "application version null": ("application", .map([.utf8String("version"): .null])),
            "application build integer": ("application", .map([.utf8String("build"): .unsignedInt(418)])),
            "device null": ("device", .null),
            "device without model": ("device", .map([.utf8String("formFactor"): .utf8String("phone")])),
            "device without formFactor": ("device", .map([.utf8String("model"): .utf8String("iPhone17,1")])),
            "device formFactor null": ("device", .map([.utf8String("model"): .utf8String("iPhone17,1"), .utf8String("formFactor"): .null])),
            "device formFactor integer": ("device", .map([.utf8String("model"): .utf8String("iPhone17,1"), .utf8String("formFactor"): .unsignedInt(1)])),
            "operatingSystem null": ("operatingSystem", .null),
            "operatingSystem without version": ("operatingSystem", .map([.utf8String("name"): .utf8String("iOS")])),
            "operatingSystem name integer": ("operatingSystem", .map([.utf8String("name"): .unsignedInt(1), .utf8String("version"): .utf8String("26.1.0")])),
            "locale null": ("locale", .null),
            "locale integer": ("locale", .unsignedInt(1)),
            "network null": ("network", .null),
            "network integer": ("network", .unsignedInt(0)),
        ]
        let (member, value) = try #require(members[kind])
        // Under the context map, but for the map itself.
        let context: SwiftCBOR.CBOR = member == "context" ? value : .map([.utf8String(member): value])
        let directory = FilePath(NSTemporaryDirectory()).appending("IndependentCBORContextTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let payload: [UInt8] = [0] + SwiftCBOR.CBOR.map([
            .utf8String("id"): .utf8String("6F9619FF-8B86-D011-B42D-00C04FC964FF"),
            .utf8String("timestamp"): .double(2.5),
            .utf8String("name"): .utf8String("Tapped"),
            .utf8String("version"): .unsignedInt(1),
            .utf8String("context"): context,
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

    @Test("A form factor or network name no case has, as a later release might write, reads as that key absent, and the record is recovered with the rest of its context", arguments: ["device", "network"])
    func unknownNameReadsAsAbsent(member: String) throws {
        // SwiftCBOR's values aren't Sendable, so a test argument names one.
        let value: SwiftCBOR.CBOR = member == "device"
            ? .map([.utf8String("model"): .utf8String("Car1,1"), .utf8String("formFactor"): .utf8String("car")])
            : .utf8String("satellite")
        let directory = FilePath(NSTemporaryDirectory()).appending("IndependentCBORContextTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let payload: [UInt8] = [0] + SwiftCBOR.CBOR.map([
            .utf8String("id"): .utf8String("6F9619FF-8B86-D011-B42D-00C04FC964FF"),
            .utf8String("timestamp"): .double(2.5),
            .utf8String("name"): .utf8String("Tapped"),
            .utf8String("version"): .unsignedInt(1),
            .utf8String("context"): .map([.utf8String("screen"): .utf8String("Cart"), .utf8String(member): value]),
            .utf8String("event"): .map([.utf8String("number"): .unsignedInt(7)]),
        ]).encode()
        let checksum = payload.withUnsafeBytes { CRC32.checksum(of: $0) }
        let segment: [UInt8] = [0x54, 0x52, 0x46, 0x4C, 3, 0, 0, 0]
            + withUnsafeBytes(of: UInt32(payload.count).littleEndian) { Array($0) }
            + withUnsafeBytes(of: checksum.littleEndian) { Array($0) }
            + payload
        try FileManager.default.createDirectory(atPath: directory.string, withIntermediateDirectories: true)
        try #require(FileManager.default.createFile(atPath: directory.appending("00000000000000000001.segment").string, contents: Data(segment)))
        let expectedNumber = 7
        let expectedScreen = "Cart"

        let recovered = try SegmentStore(events: [Tapped.self], directory: directory).takeRecoveredRecords()

        let actual = try #require(recovered.first)
        #expect(recovered.count == 1)
        #expect((actual.event as? Tapped)?.number == expectedNumber)
        #expect(actual.context[ScreenKey.self] == expectedScreen)
        #expect(actual.context[DeviceKey.self] == nil)
        #expect(actual.context[NetworkKey.self] == nil)
        #expect(actual.context.count == 1)
    }

    @Test("A sample rate of exactly 0 or 1 written by another encoder, the bounds a rate may take, reads back as that rate", arguments: [0.0, 1.0])
    func sampleRateBoundsRead(rate: Double) throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("IndependentCBORContextTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let payload: [UInt8] = [0] + SwiftCBOR.CBOR.map([
            .utf8String("id"): .utf8String("6F9619FF-8B86-D011-B42D-00C04FC964FF"),
            .utf8String("timestamp"): .double(2.5),
            .utf8String("name"): .utf8String("Tapped"),
            .utf8String("version"): .unsignedInt(1),
            .utf8String("context"): .map([.utf8String("sampleRate"): .double(rate)]),
            .utf8String("event"): .map([.utf8String("number"): .unsignedInt(7)]),
        ]).encode()
        let checksum = payload.withUnsafeBytes { CRC32.checksum(of: $0) }
        let segment: [UInt8] = [0x54, 0x52, 0x46, 0x4C, 3, 0, 0, 0]
            + withUnsafeBytes(of: UInt32(payload.count).littleEndian) { Array($0) }
            + withUnsafeBytes(of: checksum.littleEndian) { Array($0) }
            + payload
        try FileManager.default.createDirectory(atPath: directory.string, withIntermediateDirectories: true)
        try #require(FileManager.default.createFile(atPath: directory.appending("00000000000000000001.segment").string, contents: Data(segment)))
        let expected = try SampleRate(rate)

        let recovered = try SegmentStore(events: [Tapped.self], directory: directory).takeRecoveredRecords()

        let actual = recovered.map { $0.context[SampleRateKey.self] }
        #expect(actual == [expected])
    }
}

extension IndependentCBORContextTests.Tapped: Codable {}
