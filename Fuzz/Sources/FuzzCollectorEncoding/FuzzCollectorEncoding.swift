// CollectorBatchDecoder against a model, in three modes the first choice picks:
//
// - Any bytes as a body: batch(from:) throws NotACollectorBatch, or decodes and reports between
//   them exactly as many records as Foundation's JSONSerialization finds in the body's `records`
//   array, each offset once, in order; and the records it decodes encode to a body that decodes
//   to the same records with none left out, and encodes again to the same bytes.
// - A body built from choices: up to four records, each member valid or broken in one of a few
//   ways (an id that isn't a UUID, an unknown event, a timestamp of another form, a property of
//   the wrong type or out of its type's range, a malformed session). A record decodes exactly when
//   every one of its members is valid, keeping its id, timestamp, properties and session.
// - Timestamps: a millisecond count's timestamp parses back to a date with the same timestamp, and
//   any text parses to nil or to a date whose timestamp is that text, both read through the
//   decoder.

import CollectorEncoding
import Events
import Foundation
import FuzzSupport
import JSONValues
import PropertyJSON
import TrackingPlans

/// A hand-written event, coded as `@Event` codes one: each property under its name, a Date as its
/// seconds since 2001, an optional's nil left out.
struct Probe: Event, Codable, Equatable {
    static let name = "probe"
    static let schema = EventSchema(name: "probe", version: 1, consentCategory: .analytics, properties: [
        .init(name: "small", typeName: "UInt8", isOptional: false),
        .init(name: "ratio", typeName: "Double", isOptional: false),
        .init(name: "at", typeName: "Date", isOptional: false),
        .init(name: "note", typeName: "String", isOptional: true),
    ])

    var small: UInt8
    var ratio: Double
    var at: Date
    var note: String?

    enum CodingKeys: String, CodingKey {
        case small, ratio, at, note
    }

    init(small: UInt8, ratio: Double, at: Date, note: String?) {
        self.small = small
        self.ratio = ratio
        self.at = at
        self.note = note
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        small = try container.decode(UInt8.self, forKey: .small)
        ratio = try container.decode(Double.self, forKey: .ratio)
        at = Date(timeIntervalSinceReferenceDate: try container.decode(Double.self, forKey: .at))
        note = try container.decodeIfPresent(String.self, forKey: .note)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(small, forKey: .small)
        try container.encode(ratio, forKey: .ratio)
        try container.encode(at.timeIntervalSinceReferenceDate, forKey: .at)
        try container.encodeIfPresent(note, forKey: .note)
    }
}

/// A millisecond count from up to six choices, within about ±4,400 years of 1970.
func milliseconds(_ input: inout FuzzInput) -> Int64 {
    var value: Int64 = 0
    for _ in 0 ..< 6 {
        value = value << 8 | Int64(input.byte())
    }
    return value % 140_000_000_000_000 - 70_000_000_000_000
}

/// The date of `milliseconds`: its start, or the next Double up when that rounds down below it.
func date(_ milliseconds: Int64) -> Date {
    var seconds = Double(milliseconds) / 1000 - Date.timeIntervalBetween1970AndReferenceDate
    while (try? Date(timeIntervalSinceReferenceDate: seconds).millisecondsSince1970()) ?? milliseconds < milliseconds {
        seconds = seconds.nextUp
    }
    return Date(timeIntervalSinceReferenceDate: seconds)
}

func quoted(_ text: String) -> String {
    "\"" + text + "\""
}

func checkAnyBody(_ body: Data, decoder: CollectorBatchDecoder, encoder: CollectorBatchEncoder) {
    let decoded: DecodedCollectorBatch
    do {
        decoded = try decoder.batch(from: body)
    } catch {
        return
    }
    let object = try? JSONSerialization.jsonObject(with: body, options: [.fragmentsAllowed]) as? [String: Any]
    let expectedCount = (object?["records"] as? [Any])?.count
    check(expectedCount == decoded.records.count + decoded.undecodedRecords.count, "decoded \(decoded.records.count) and reported \(decoded.undecodedRecords.count) of \(String(describing: expectedCount)) records")
    let offsets = decoded.undecodedRecords.map(\.offset)
    check(offsets == offsets.sorted() && Set(offsets).count == offsets.count, "offsets \(offsets) out of order")
    check(offsets.allSatisfy { $0 >= 0 && $0 < (expectedCount ?? 0) }, "an offset outside the records")
    let encoded = encoder.batch(of: decoded.records)
    check(encoded.skippedRecords.isEmpty, "a decoded record didn't encode: \(encoded.skippedRecords)")
    guard let first = encoded.body?.body else {
        check(decoded.records.isEmpty, "decoded records encoded to no body")
        return
    }
    guard let again = try? decoder.batch(from: first) else {
        check(false, "the decoder's own records didn't decode again")
        return
    }
    check(again.undecodedRecords.isEmpty, "a re-encoded record didn't decode: \(again.undecodedRecords)")
    check(again.records.map(\.id) == decoded.records.map(\.id), "re-encoded records changed ids")
    check(encoder.batch(of: again.records).body?.body == first, "a second round trip changed the bytes")
}

func checkBuiltBody(_ input: inout FuzzInput, decoder: CollectorBatchDecoder) {
    let count = input.int(in: 0 ... 4)
    var texts: [String] = []
    var expected: [(id: UUID, milliseconds: Int64, small: Int, ratio: Double, at: Int64, note: String?, session: UUID?)?] = []
    for index in 0 ..< count {
        var valid = true
        let id = UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", index)) ?? UUID()
        let idText: String
        switch input.int(below: 4) {
        case 0: idText = quoted("not-a-uuid"); valid = false
        default: idText = quoted(id.uuidString)
        }
        let nameText: String
        switch input.int(below: 5) {
        case 0: nameText = quoted("unknown"); valid = false
        case 1: nameText = "5"; valid = false
        default: nameText = quoted("probe")
        }
        let millisecond = milliseconds(&input)
        let timestampText: String
        switch input.int(below: 5) {
        case 0: timestampText = quoted("1970-01-01T00:00:00Z"); valid = false
        default: timestampText = quoted((try? date(millisecond).iso8601Timestamp) ?? "")
        }
        // 0 ... 299: past 255 is out of a UInt8's range.
        let small = input.int(below: 150) * 2
        if small > 255 { valid = false }
        let ratio = Double(input.int(below: 256) - 128) / Double(input.int(in: 1 ... 4))
        let note: String? = input.int(below: 2) == 0 ? nil : "n\(input.byte())"
        let ratioText: String
        switch input.int(below: 6) {
        case 0: ratioText = quoted("1"); valid = false
        default: ratioText = JSON.number(ratio).minified
        }
        let atMillisecond = milliseconds(&input)
        let atText = quoted((try? date(atMillisecond).iso8601Timestamp) ?? "")
        let session: UUID? = input.int(below: 2) == 0 ? nil : UUID(uuidString: String(format: "00000000-0000-7000-8000-%012d", input.byte()))
        var contextText = session.map { #"{"session":"# + quoted($0.uuidString) + "}" } ?? "{}"
        if input.int(below: 6) == 0 {
            contextText = #"{"session":"nope"}"#
            valid = false
        }
        let properties = #"{"at":"# + atText + #","note":"# + (note.map(quoted) ?? "null") + #","ratio":"# + ratioText + #","small":"# + String(small) + "}"
        texts.append(#"{"context":"# + contextText + #","id":"# + idText + #","isRedelivered":false,"name":"# + nameText + #","properties":"# + properties + #","timestamp":"# + timestampText + "}")
        expected.append(valid ? (id, millisecond, small, ratio, atMillisecond, note, session) : nil)
    }
    let body = Data((#"{"records":["# + texts.joined(separator: ",") + "]}").utf8)
    guard let decoded = try? decoder.batch(from: body) else {
        check(false, "a built batch threw")
        return
    }
    let kept = expected.compactMap { $0 }
    check(decoded.records.count == kept.count, "decoded \(decoded.records.count) of the \(kept.count) valid records")
    check(decoded.undecodedRecords.map(\.offset) == expected.indices.filter { expected[$0] == nil }, "reported \(decoded.undecodedRecords.map(\.offset))")
    for (record, model) in zip(decoded.records, kept) {
        let event = record.event as? Probe
        check(record.id == model.id, "id \(record.id)")
        check((try? record.timestamp.millisecondsSince1970()) == model.milliseconds, "timestamp \(record.timestamp)")
        check(event.map { Int($0.small) } == model.small, "small \(String(describing: event?.small))")
        check(event?.ratio == model.ratio, "ratio \(String(describing: event?.ratio))")
        check((try? event?.at.millisecondsSince1970()) == model.at, "at \(String(describing: event?.at))")
        check(event?.note == model.note, "note \(String(describing: event?.note))")
        check(record.context[SessionKey.self] == model.session, "session")
    }
}

/// The record's timestamp parsed from `text`, through the decoder (the parser is package API, out of
/// this package's reach), or nil when the record is reported.
func parsedTimestamp(_ text: String, decoder: CollectorBatchDecoder) -> Date? {
    let body = #"{"records":[{"context":{},"id":"00000000-0000-4000-8000-000000000001","isRedelivered":false,"name":"probe","properties":{"at":"2001-01-01T00:00:00.000Z","ratio":0,"small":0},"timestamp":"# + quoted(text) + "}]}"
    return (try? decoder.batch(from: Data(body.utf8)))?.records.first?.timestamp
}

func checkTimestamps(_ input: inout FuzzInput, decoder: CollectorBatchDecoder) {
    let millisecond = milliseconds(&input)
    if let text = try? date(millisecond).iso8601Timestamp {
        let parsed = parsedTimestamp(text, decoder: decoder)
        check(parsed != nil, "\(text) didn't parse")
        check((try? parsed?.iso8601Timestamp) == text, "\(text) parsed to another timestamp")
        check((try? parsed?.millisecondsSince1970()) == millisecond, "\(text) parsed to another millisecond")
    }
    // Text of the timestamp's own characters, so near misses are common.
    let alphabet = Array("0123456789-T:.Z+z ")
    var text = ""
    for _ in 0 ..< input.int(in: 0 ... 32) {
        text.append(alphabet[input.int(below: alphabet.count)])
    }
    if let parsed = parsedTimestamp(text, decoder: decoder) {
        check((try? parsed.iso8601Timestamp) == text, "\(text) parsed to a date of another timestamp")
    }
}

@main
enum FuzzCollectorEncoding {
    static func main() {
        // Made once: a decoder of Probe through its own schema, and an encoder of the same plan.
        guard let plan = try? TrackingPlan(schemas: [Probe.schema]),
              let decoder = try? CollectorBatchDecoder(plan: plan, events: [Probe.self])
        else {
            check(false, "the plan or decoder didn't build")
            return
        }
        let encoder = CollectorBatchEncoder(plan: plan)
        runFuzzer { input in
            switch input.int(below: 3) {
            case 0:
                var bytes: [UInt8] = []
                while !input.isEmpty {
                    bytes.append(UInt8(input.byte()))
                }
                checkAnyBody(Data(bytes), decoder: decoder, encoder: encoder)
            case 1:
                checkBuiltBody(&input, decoder: decoder)
            default:
                checkTimestamps(&input, decoder: decoder)
            }
        }
    }
}
