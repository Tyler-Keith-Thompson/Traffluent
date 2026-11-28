// SegmentStore's recovery against a model of the segment format: a segment file is built from
// choices (records, delivery marks, records it can't decode, garbage), then damaged (a byte
// flipped, the tail cut, raw bytes appended) or replaced by raw bytes outright, and a store is
// opened on it. The model reads the bytes as the format says (a header, then frames of length,
// CRC-32 and payload, up to the first that isn't intact) and must agree with recovery: the same
// records, in order, each from a frame whose checksum holds, with the identifier its frame holds
// and the redelivery marks the intact frames give, and the file cut to the intact prefix, or
// deleted when nothing is left to deliver. A segment with records it can't decode beside ones it
// can is rewritten to the decodable frames, renumbered, then one mark of their new numbers; a
// second store opened on it recovers the same records and reports nothing.
// A segment whose header names a later version is left as it is, and nothing is read from it.
// Record payloads are written here as the model's own CBOR (RFC 8949), not through the CBOR
// package's encoder: a record with its keys in another order or with keys the store doesn't know must still
// decode, and so must one without a version, read by name like one at its type's version; one
// missing a required key,
// holding a value of another type, an unknown event type, bytes past its map or a version other
// than its type's must not. A record's session, a UUID string under `session`, comes back as its
// context's SessionKey, and one without it comes back sessionless (TRAF-122); a session that
// isn't a UUID string, null included, makes the record undecodable. So do the other context keys
// a store keeps (TRAF-145), members of a map under `context`: the sample rate (a double in
// 0 ... 1 under `sampleRate`), the screen (text under `screen`), the app (a map of
// `bundleIdentifier`, `version` and `build`, each there or not, under `application`), the device
// (a map of `model` and its form factor's name under `device`), the operating system (a map of
// `name` and `version` under `operatingSystem`), the locale (its identifier under `locale`) and
// the network connection (its name under `network`). Each comes back as its key, or the key is
// absent when the member is; a member of another name is skipped; a form factor or network name
// no case has, as a later release might write, reads as that key absent (the whole device, for a
// form factor) and the record is kept; and a member holding anything else, null included, or a
// `context` that isn't a map, makes the record undecodable.

import AsyncQueues
import Checksums
import Events
import Foundation
import FuzzSupport
import Persistence
import Synchronization

struct Tapped: Event, Hashable {
    var number: Int
    var label: String
}

// Swift's synthesized conformance, as an app's own event type has.
extension Tapped: Codable {}

@main
enum FuzzPersistence {
    static func main() { runFuzzer(fuzz) }

    static let header: [UInt8] = [0x54, 0x52, 0x46, 0x4C, 3, 0, 0, 0]

    /// A frame of `payload`: its length and CRC-32, little-endian, then the payload.
    static func frame(_ payload: [UInt8]) -> [UInt8] {
        let checksum = payload.withUnsafeBytes { CRC32.checksum(of: $0) }
        return littleEndian(UInt32(payload.count)) + littleEndian(checksum) + payload
    }

    static func littleEndian(_ value: UInt32) -> [UInt8] {
        (0 ..< 4).map { UInt8(truncatingIfNeeded: value >> (8 * $0)) }
    }

    /// A CBOR head: the major type in the top three bits, the argument in the fewest bytes.
    static func head(_ majorType: UInt8, _ argument: UInt64) -> [UInt8] {
        let initial = majorType << 5
        switch argument {
        case 0 ..< 24: return [initial | UInt8(argument)]
        case 24 ... 0xFF: return [initial | 24, UInt8(argument)]
        case 0x100 ... 0xFFFF: return [initial | 25] + bigEndian(argument, count: 2)
        case 0x1_0000 ... 0xFFFF_FFFF: return [initial | 26] + bigEndian(argument, count: 4)
        default: return [initial | 27] + bigEndian(argument, count: 8)
        }
    }

    static func bigEndian(_ value: UInt64, count: Int) -> [UInt8] {
        (0 ..< count).reversed().map { UInt8(truncatingIfNeeded: value >> (8 * UInt64($0))) }
    }

    static func text(_ string: String) -> [UInt8] {
        head(3, UInt64(string.utf8.count)) + Array(string.utf8)
    }

    static func integer(_ value: Int) -> [UInt8] {
        value < 0 ? head(1, UInt64(-1 - value)) : head(0, UInt64(value))
    }

    /// A double-precision float.
    static func double(_ value: Double) -> [UInt8] {
        [0xFB] + bigEndian(value.bitPattern, count: 8)
    }

    /// A CBOR map of `entries`, in order.
    static func map(_ entries: [(key: String, value: [UInt8])]) -> [UInt8] {
        head(5, UInt64(entries.count)) + entries.flatMap { text($0.key) + $0.value }
    }

    /// A record's payload as the format lays it out, kind byte first: a map of its identifier,
    /// timestamp, event name, version (left out when `nil`, a record with no version to compare),
    /// call site and event, with `extra` entries after them.
    static func recordPayload(id: UUID, name: String, version: Int? = 1, event: [UInt8], extra: [(key: String, value: [UInt8])] = []) -> [UInt8] {
        recordPayload(id: id, name: name, version: version, context: [], event: event, extra: extra)
    }

    /// The payload of a record whose context members, `session` and `context`, are `context`,
    /// before its event.
    static func recordPayload(id: UUID, name: String, version: Int?, context: [(key: String, value: [UInt8])], event: [UInt8], extra: [(key: String, value: [UInt8])]) -> [UInt8] {
        let location = map([("fileID", text("App/File.swift")), ("function", text("f()")), ("line", integer(1)), ("column", integer(1))])
        var entries: [(key: String, value: [UInt8])] = [
            ("id", text(id.uuidString)),
            // 0.0 as a double-precision float.
            ("timestamp", [0xFB, 0, 0, 0, 0, 0, 0, 0, 0]),
            ("name", text(name)),
        ]
        if let version {
            entries.append(("version", integer(version)))
        }
        entries.append(("sourceLocation", location))
        entries += context
        entries.append(("event", event))
        return [0] + map(entries + extra)
    }

    /// `event`'s map, its keys in the declaration's order or reversed, and an entry the type
    /// doesn't have (a property removed since) when `unknown` is set.
    static func eventMap(_ event: Tapped, reversed: Bool, unknown: Bool) -> [UInt8] {
        var entries: [(key: String, value: [UInt8])] = [("number", integer(event.number)), ("label", text(event.label))]
        if reversed { entries.reverse() }
        if unknown { entries.insert(("removed", head(4, 2) + integer(1) + text("x")), at: 1) }
        return map(entries)
    }

    /// A record frame the fuzzer built: the record's identifier, event and the context keys it
    /// holds.
    struct Built: Hashable {
        var id: UUID
        var event: Tapped
        var session: UUID?
        var sampleRate: Double?
        var screen: String?
        var application: ApplicationKey.Value?
        var device: DeviceKey.Value?
        var operatingSystem: OperatingSystemKey.Value?
        var locale: String?
        var network: NetworkKey.Value?

        /// How many keys a recovered record's context holds.
        var contextCount: Int {
            [session != nil, sampleRate != nil, screen != nil, application != nil, device != nil, operatingSystem != nil, locale != nil, network != nil].filter { $0 }.count
        }
    }

    /// Each network connection and its name in a record map.
    /// Each network connection and its name in a record map, and a name no case has, which reads as
    /// no connection.
    static let networks: [(name: String, value: NetworkKey.Value?)] = [("wifi", .wifi), ("cellular", .cellular), ("wiredEthernet", .wiredEthernet), ("other", .other), ("offline", .offline), ("satellite", nil)]

    /// Each form factor and its name in a record map, and a name no case has, which reads as no
    /// device.
    static let formFactors: [(name: String, value: DeviceKey.Value.FormFactor?)] = [("phone", .phone), ("pad", .pad), ("mac", .mac), ("tv", .tv), ("watch", .watch), ("vision", .vision), ("car", nil)]

    /// What the model reads from a segment's bytes.
    struct Reading {
        /// Header plus intact frames; 0 when the header isn't the format's.
        var validByteCount = 0
        /// Each intact record frame's number and payload, in order.
        var records: [(index: UInt32, payload: [UInt8])] = []
        var marked: Set<UInt32> = []
        /// Whether the header names a later version than 3, which recovery leaves alone.
        var isNewerVersion = false
    }

    /// The format, read the obvious way.
    static func read(_ bytes: [UInt8]) -> Reading {
        var reading = Reading()
        guard bytes.count >= 8, Array(bytes[0 ..< 4]) == Array(header[0 ..< 4]) else { return reading }
        if Int(bytes[4]) | Int(bytes[5]) << 8 > 3 {
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
        // Each built payload (without its kind byte) and the record it decodes to, if any.
        var built: [[UInt8]: Built?] = [:]
        var bytes: [UInt8]
        if input.int(below: 8) == 0 {
            bytes = []
            while !input.isEmpty { bytes.append(UInt8(input.byte())) }
        } else {
            bytes = input.int(below: 16) == 0 ? [0x54, 0x52, 0x46, 0x4C, UInt8(input.int(below: 5)), 0, 0, 0] : header
            var records: UInt32 = 0
            while !input.isEmpty {
                switch input.int(below: 8) {
                case 0, 1, 2:
                    let event = Tapped(number: input.int(in: -30 ... 300), label: String(repeating: "é", count: input.int(below: 4)))
                    // Identifiers from a few values, so two frames can share one and recovery
                    // must still give each record its own frame's.
                    let id = UUID(uuid: (UInt8(input.int(below: 4)), 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
                    // Keys reordered, or ones the store doesn't know, in the event or the record:
                    // written by another release, and still decodable.
                    let eventBytes = eventMap(event, reversed: input.int(below: 2) == 0, unknown: input.int(below: 2) == 0)
                    let extra: [(key: String, value: [UInt8])] = input.int(below: 2) == 0 ? [("unknown", map([("k", text("v"))]))] : []
                    // Version 1, written or left out.
                    let version: Int? = input.int(below: 3) == 0 ? nil : 1
                    // A session from a few values, in uppercase as Foundation writes it or in
                    // lowercase, which reads back as the same UUID; or none, as a record tracked
                    // without one, or written before stores kept sessions, has.
                    let session: UUID? = input.int(below: 3) == 0 ? nil : UUID(uuid: (0x01, 0x9A, 0, 0, 0, 0, 0x70, 0, 0x80, 0, 0, 0, 0, 0, 0, UInt8(input.int(below: 3))))
                    let sessionText = session.map { input.int(below: 4) == 0 ? $0.uuidString.lowercased() : $0.uuidString }
                    // The other kept keys, each there or not, at their bounds among their values.
                    let sampleRate: Double? = input.int(below: 2) == 0 ? nil : [0, 0.25, 1, .leastNonzeroMagnitude, 1.0.nextDown][input.int(below: 5)]
                    let screen: String? = input.int(below: 2) == 0 ? nil : ["", "Cart", "Checkout"][input.int(below: 3)]
                    let network = input.int(below: 2) == 0 ? nil : networks[input.int(below: networks.count)]
                    let system: OperatingSystemKey.Value? = input.int(below: 2) == 0 ? nil : OperatingSystemKey.Value(name: "iOS", version: "26.\(input.int(below: 3)).0")
                    let application: ApplicationKey.Value? = input.int(below: 2) == 0 ? nil : ApplicationKey.Value(
                        bundleIdentifier: input.int(below: 2) == 0 ? nil : "com.example.shop",
                        version: input.int(below: 2) == 0 ? nil : "2.4.\(input.int(below: 3))",
                        build: input.int(below: 2) == 0 ? nil : ""
                    )
                    let device = input.int(below: 2) == 0 ? nil : (model: ["", "iPhone17,1"][input.int(below: 2)], formFactor: formFactors[input.int(below: formFactors.count)])
                    let locale: String? = input.int(below: 2) == 0 ? nil : ["en", "fr_CA", "ja_JP"][input.int(below: 3)]
                    var members: [(key: String, value: [UInt8])] = []
                    if let sampleRate { members.append(("sampleRate", double(sampleRate))) }
                    if let screen { members.append(("screen", text(screen))) }
                    if let network { members.append(("network", text(network.name))) }
                    if let system { members.append(("operatingSystem", map([("name", text(system.name)), ("version", text(system.version))]))) }
                    if let application {
                        var fields: [(key: String, value: [UInt8])] = []
                        if let value = application.bundleIdentifier { fields.append(("bundleIdentifier", text(value))) }
                        if let value = application.version { fields.append(("version", text(value))) }
                        if let value = application.build { fields.append(("build", text(value))) }
                        members.append(("application", map(fields)))
                    }
                    if let device { members.append(("device", map([("model", text(device.model)), ("formFactor", text(device.formFactor.name))]))) }
                    if let locale { members.append(("locale", text(locale))) }
                    // In another order too, as another encoder might write them, and with a member
                    // of another name, as a later release might add.
                    if input.int(below: 2) == 0 { members.reverse() }
                    if input.int(below: 4) == 0 { members.insert(("region", text("eu-west")), at: 0) }
                    var context: [(key: String, value: [UInt8])] = []
                    if let sessionText { context.append(("session", text(sessionText))) }
                    if !members.isEmpty { context.append(("context", map(members))) }
                    let payload = recordPayload(id: id, name: "Tapped", version: version, context: context, event: eventBytes, extra: extra)
                    built[Array(payload.dropFirst())] = Built(
                        id: id, event: event, session: session, sampleRate: sampleRate, screen: screen, application: application,
                        device: device.flatMap { device in device.formFactor.value.map { DeviceKey.Value(model: device.model, formFactor: $0) } },
                        operatingSystem: system, locale: locale, network: network.flatMap(\.value)
                    )
                    bytes += frame(payload)
                    records += 1
                case 3:
                    // A record the store can't decode: an unlisted type, bytes past its map, an
                    // event missing a required property, one whose property has another type, a
                    // readable event stored at another version than Tapped's, 1, or one whose
                    // context member isn't in its form: a session that isn't a UUID string, a
                    // sample rate outside 0 ... 1 or written as an integer, a screen that isn't
                    // text, an app whose field isn't text, a device without its model or form
                    // factor, a network connection that isn't text, an operating system without
                    // its version, a locale that isn't text, or null.
                    let id = UUID(uuid: (9, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
                    let payload: [UInt8]
                    switch input.int(below: 6) {
                    case 5:
                        let members: [(key: String, value: [UInt8])] = [
                            ("session", integer(7)), ("session", text("not-a-uuid")), ("session", map([])), ("session", [0xF6]),
                            ("sampleRate", double(1.0.nextUp)), ("sampleRate", double(-Double.leastNonzeroMagnitude)), ("sampleRate", double(.nan)), ("sampleRate", integer(1)), ("sampleRate", [0xF6]),
                            ("screen", integer(3)), ("screen", [0xF6]),
                            ("application", [0xF6]), ("application", text("com.example.shop")), ("application", map([("version", [0xF6])])), ("application", map([("build", integer(418))])),
                            ("device", [0xF6]), ("device", map([("formFactor", text("phone"))])), ("device", map([("model", text("iPhone17,1"))])), ("device", map([("model", text("iPhone17,1")), ("formFactor", [0xF6])])), ("device", map([("model", text("iPhone17,1")), ("formFactor", integer(1))])),
                            ("locale", [0xF6]), ("locale", integer(1)),
                            ("network", integer(0)), ("network", [0xF6]),
                            ("operatingSystem", map([("name", text("iOS"))])), ("operatingSystem", [0xF6]),
                            ("context", [0xF6]), ("context", text("Checkout")), ("context", integer(1)),
                        ]
                        let member = members[input.int(below: members.count)]
                        // The session is a member of the record map, the rest of the context map,
                        // which is itself malformed in the last cases.
                        let context: (key: String, value: [UInt8]) = switch member.key {
                        case "session", "context": member
                        default: ("context", map([member]))
                        }
                        payload = recordPayload(id: id, name: "Tapped", version: 1, context: [context], event: eventMap(Tapped(number: 0, label: ""), reversed: false, unknown: false), extra: [])
                    case 0: payload = recordPayload(id: id, name: "Other", event: map([]))
                    case 1: payload = recordPayload(id: id, name: "Tapped", event: eventMap(Tapped(number: 0, label: ""), reversed: false, unknown: false)) + [0x00]
                    case 2: payload = recordPayload(id: id, name: "Tapped", event: map([("number", integer(1))]))
                    case 3: payload = recordPayload(id: id, name: "Tapped", version: [0, 2, 7][input.int(below: 3)], event: eventMap(Tapped(number: 0, label: ""), reversed: false, unknown: false))
                    default: payload = recordPayload(id: id, name: "Tapped", event: map([("number", text("1")), ("label", text(""))]))
                    }
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
        var expected: [(record: Built, isRedelivered: Bool, frame: Int)] = []
        var collision = false
        for (position, record) in model.records.enumerated() {
            guard let decoded = built[record.payload] else {
                // An intact frame the fuzzer didn't build means a CRC-32 collision; nothing to compare.
                collision = true
                break
            }
            if let decoded {
                expected.append((decoded, model.marked.contains(record.index), position))
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
            check(record.event as? Tapped == expectation.record.event, "recovered \(record.event), model \(expectation.record.event)")
            check(record.id == expectation.record.id, "recovered identifier \(record.id), model \(expectation.record.id)")
            check(record.isRedelivered == expectation.isRedelivered, "redelivered \(record.isRedelivered), model \(expectation.isRedelivered)")
            check(record.context[SessionKey.self] == expectation.record.session, "recovered session \(String(describing: record.context[SessionKey.self])), model \(String(describing: expectation.record.session))")
            check(record.context[SampleRateKey.self]?.value == expectation.record.sampleRate, "recovered sample rate \(String(describing: record.context[SampleRateKey.self])), model \(String(describing: expectation.record.sampleRate))")
            check(record.context[ScreenKey.self] == expectation.record.screen, "recovered screen \(String(describing: record.context[ScreenKey.self])), model \(String(describing: expectation.record.screen))")
            check(record.context[NetworkKey.self] == expectation.record.network, "recovered network \(String(describing: record.context[NetworkKey.self])), model \(String(describing: expectation.record.network))")
            check(record.context[OperatingSystemKey.self] == expectation.record.operatingSystem, "recovered operating system \(String(describing: record.context[OperatingSystemKey.self])), model \(String(describing: expectation.record.operatingSystem))")
            check(record.context[ApplicationKey.self] == expectation.record.application, "recovered app \(String(describing: record.context[ApplicationKey.self])), model \(String(describing: expectation.record.application))")
            check(record.context[DeviceKey.self] == expectation.record.device, "recovered device \(String(describing: record.context[DeviceKey.self])), model \(String(describing: expectation.record.device))")
            check(record.context[LocaleKey.self]?.identifier == expectation.record.locale, "recovered locale \(String(describing: record.context[LocaleKey.self])), model \(String(describing: expectation.record.locale))")
            // Only the members the record holds come back: an entry of another name, in the record
            // map or the context map, is no key.
            check(record.context.count == expectation.record.contextCount, "recovered a context of \(record.context.count) values, model \(expectation.record.contextCount)")
        }
        // Dropped records beside ones to deliver: the segment is rewritten without them.
        let isRewritten = !expected.isEmpty && expected.count < model.records.count
        for (offset, (record, expectation)) in zip(recovered, expected).enumerated() {
            let index = UInt32(truncatingIfNeeded: record.deliveryTag?.position ?? .max)
            let expectedIndex = isRewritten ? UInt32(offset) : model.records[expectation.frame].index
            check(index == expectedIndex, "position \(index) for frame \(expectation.frame), model \(expectedIndex)")
        }

        // Read back by position, as a delivery does for a batch a full buffer dropped, each
        // recovered record comes back as recovery gave it, and a position never written gives none.
        if let acknowledger = recovered.first?.deliveryTag?.acknowledger {
            let positions = recovered.compactMap { $0.deliveryTag?.position }
            let readBack = acknowledger.records(at: positions.reversed() + [UInt64.max])
            check(readBack.count == recovered.count, "read back \(readBack.count) records, recovered \(recovered.count)")
            for record in recovered {
                let match = readBack.first { $0.deliveryTag?.position == record.deliveryTag?.position }
                check(match?.event as? Tapped == record.event as? Tapped, "read back \(String(describing: match?.event)), recovered \(record.event)")
                check(match?.id == record.id, "read back identifier \(String(describing: match?.id)), recovered \(record.id)")
                check(match?.context[SessionKey.self] == record.context[SessionKey.self], "read back session \(String(describing: match?.context[SessionKey.self])), recovered \(String(describing: record.context[SessionKey.self]))")
                check(match?.context[SampleRateKey.self] == record.context[SampleRateKey.self], "read back sample rate \(String(describing: match?.context[SampleRateKey.self])), recovered \(String(describing: record.context[SampleRateKey.self]))")
                check(match?.context.count == record.context.count, "read back a context of \(String(describing: match?.context.count)) values, recovered \(record.context.count)")
            }
        }

        let contents = FileManager.default.contents(atPath: path)
        if model.isNewerVersion {
            check(recovered.isEmpty, "recovered \(recovered.count) records from a newer version's segment")
            check(contents == Data(bytes), "a newer version's segment was changed")
        } else if expected.isEmpty {
            check(contents == nil, "a segment with nothing to deliver was kept, \(contents?.count ?? 0) bytes")
        } else if isRewritten {
            let marks = expected.indices.filter { expected[$0].isRedelivered }.map { UInt32($0) }
            let rewritten = header
                + expected.flatMap { frame([0] + model.records[$0.frame].payload) }
                + (marks.isEmpty ? [] : frame([1] + marks.flatMap(littleEndian)))
            check(contents == Data(rewritten), "segment rewritten to \(contents?.count ?? -1) bytes, model \(rewritten.count)")
        } else {
            check(contents?.count == model.validByteCount, "segment cut to \(contents?.count ?? -1) bytes, model \(model.validByteCount)")
        }
        guard !model.isNewerVersion, !expected.isEmpty else { return }

        // The next launch finds what this one left: the same records, numbered in order, and no
        // drop to report.
        let reports: AsyncQueue<DropReport>
        var again: [(event: Tapped?, id: UUID, isRedelivered: Bool, index: UInt32, session: UUID?)] = []
        do {
            let next: SegmentStore
            do {
                next = try SegmentStore(events: [Tapped.self], directory: .init(directory))
            } catch {
                check(false, "the second recovery threw \(error)")
                return
            }
            reports = next.dropReports
            again = next.takeRecoveredRecords().map { record in
                (record.event as? Tapped, record.id, record.isRedelivered, UInt32(truncatingIfNeeded: record.deliveryTag?.position ?? .max), record.context[SessionKey.self])
            }
        }
        check(again.count == expected.count, "the second recovery found \(again.count) records, model \(expected.count)")
        for (offset, (record, expectation)) in zip(again, expected).enumerated() {
            check(record.event == expectation.record.event, "the second recovery found \(String(describing: record.event)), model \(expectation.record.event)")
            check(record.id == expectation.record.id, "the second recovery's identifier \(record.id), model \(expectation.record.id)")
            check(record.isRedelivered == expectation.isRedelivered, "the second recovery's redelivered \(record.isRedelivered), model \(expectation.isRedelivered)")
            check(record.index == UInt32(offset), "the second recovery's position \(record.index), model \(offset)")
            check(record.session == expectation.record.session, "the second recovery's session \(String(describing: record.session)), model \(String(describing: expectation.record.session))")
        }
        check(FileManager.default.contents(atPath: path) == contents, "the second recovery changed the segment")
        let actualReports = allReports(reports)
        check(actualReports.isEmpty, "the second recovery reported \(actualReports)")
    }

    /// Every report `reports` yields, read until it finishes: its store is gone, so it has. The
    /// fuzzer's callback can't await, so a task reads them while it waits.
    static func allReports(_ reports: AsyncQueue<DropReport>) -> [DropReport] {
        let result = Mutex<[DropReport]>([])
        let done = DispatchSemaphore(value: 0)
        Task {
            var all: [DropReport] = []
            for await report in reports { all.append(report) }
            result.withLock { [all] in $0 = all }
            done.signal()
        }
        done.wait()
        return result.withLock { $0 }
    }
}
