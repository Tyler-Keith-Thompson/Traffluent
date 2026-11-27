import EventMacros
import Foundation
import HTTPDestinations
import PropertyBased
import PropertyJSON
import Testing
import TrackingPlans
import TraffluentTestSupport

@Suite("BatchLimit.requests(for:in:encoding:oversized:)")
struct BatchSplittingTests {
    @Event(name: "sized")
    struct Sized {
        var size: Int
        var letter: Int = 0
    }

    /// Each letter a record's string repeats, and how JSON writes it: one byte, two (é), four (an
    /// emoji), and two of escaping (a quote, a backslash).
    static let letters: [(text: String, json: String)] = [("x", "x"), ("é", "é"), ("😀", "😀"), ("\"", #"\""#), ("\\", #"\\"#)]

    struct Failure: Error, Hashable {
        var reason: String
    }

    @Test("A hand-worked batch splits by count, then by bytes, in order, leaving out the record too large and the one that throws")
    func handWorked() throws {
        // Each record's JSON is the string of `size` x's, so its bytes are size + 2, and in the
        // array envelope a request's bytes are 2, plus its records', plus a comma between each two.
        // 12 bytes take ["x","xx"] (10) but not "xxx" beside them; 8 bytes of one record leave
        // out size 7 (9 bytes); three records are the most, which ends ["","",""].
        let limit = try BatchLimit(maximumRecordCount: 3, maximumByteCount: 12, maximumRecordByteCount: 8)
        let sizes = [1, 2, 3, 7, -1, 4, 4, 1, 0, 0, 0, 0]
        let batch = sizes.map { EventRecord(event: Sized(size: $0), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil) }
        let expectedBodies = [#"["x","xx"]"#, #"["xxx"]"#, #"["xxxx"]"#, #"["xxxx","x"]"#, #"["","",""]"#, #"[""]"#]
        let expectedIDs = [[0, 1], [2], [5], [6, 7], [8, 9, 10], [11]].map { $0.map { batch[$0].id } }
        let expectedSkipped = [
            SkippedRecord(recordID: batch[3].id, eventName: "sized", schemaVersion: 1, reason: Failure(reason: "oversized 9")),
            SkippedRecord(recordID: batch[4].id, eventName: "sized", schemaVersion: 1, reason: Failure(reason: "negative")),
        ]

        let actual = limit.requests(for: batch, in: .array) { record throws(Failure) in
            let size = (record.event as? Sized)?.size ?? 0
            guard size >= 0 else { throw Failure(reason: "negative") }
            return .string(String(repeating: "x", count: size))
        } oversized: { byteCount in
            Failure(reason: "oversized \(byteCount)")
        }

        #expect(actual.requests.map(\.recordIDs) == expectedIDs)
        #expect(actual.requests.map { String(decoding: $0.body.body, as: UTF8.self) } == expectedBodies)
        #expect(actual.skippedRecords == expectedSkipped)
    }

    @Test("An empty batch makes no request and skips nothing")
    func emptyBatch() {
        let actual = BatchLimit.unlimited.requests(for: [], in: .array) { _ throws(Failure) in JSON.null } oversized: { Failure(reason: "\($0)") }

        #expect(actual.requests.isEmpty)
        #expect(actual.skippedRecords.isEmpty)
    }

    @Test("A record's bytes are its UTF-8 bytes once escaped: 13 bytes hold [\"éé\",\"\\\"\"] in one request, 12 bytes take each alone")
    func multiByteAndEscapes() throws {
        // ["éé","\""] is 2 + 6 + 1 + 4 = 13 bytes, so a 12-byte request takes them one each.
        let limit = try BatchLimit(maximumRecordCount: .max, maximumByteCount: 12, maximumRecordByteCount: .max)
        let wider = try BatchLimit(maximumRecordCount: .max, maximumByteCount: 13, maximumRecordByteCount: .max)
        let texts = ["éé", "\""]
        let batch = texts.map { _ in EventRecord(event: Sized(size: 0), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil) }
        let expectedBodies = [#"["éé"]"#, #"["\""]"#]
        let expectedWiderBodies = [#"["éé","\""]"#]
        let byID = Dictionary(uniqueKeysWithValues: zip(batch.map(\.id), texts))

        let actual = limit.requests(for: batch, in: .array) { record throws(Failure) in .string(byID[record.id] ?? "") } oversized: { Failure(reason: "\($0)") }
        let actualWider = wider.requests(for: batch, in: .array) { record throws(Failure) in .string(byID[record.id] ?? "") } oversized: { Failure(reason: "\($0)") }

        #expect(actual.requests.map { String(decoding: $0.body.body, as: UTF8.self) } == expectedBodies)
        #expect(actualWider.requests.map { String(decoding: $0.body.body, as: UTF8.self) } == expectedWiderBodies)
    }

    @Test("A record over the limit for one record by its escaped UTF-8 bytes is left out with that byte count", arguments: [("😀", 6), ("\\", 4), ("é", 4)])
    func multiByteRecordLimit(text: String, byteCount: Int) throws {
        let limit = try BatchLimit(maximumRecordCount: .max, maximumByteCount: .max, maximumRecordByteCount: byteCount - 1)
        let record = EventRecord(event: Sized(size: 0), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)
        let expectedSkipped = [SkippedRecord(recordID: record.id, eventName: "sized", schemaVersion: 1, reason: Failure(reason: "\(byteCount)"))]

        let actual = limit.requests(for: [record], in: .array) { _ throws(Failure) in .string(text) } oversized: { Failure(reason: "\($0)") }

        #expect(actual.requests.isEmpty)
        #expect(actual.skippedRecords == expectedSkipped)
    }

    @Test("One record makes one request of it alone")
    func oneRecord() {
        let record = EventRecord(event: Sized(size: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)
        let expectedBody = "[null]"

        let actual = BatchLimit.unlimited.requests(for: [record], in: .array) { _ throws(Failure) in JSON.null } oversized: { Failure(reason: "\($0)") }

        #expect(actual.requests.map(\.recordIDs) == [[record.id]])
        #expect(actual.requests.map { String(decoding: $0.body.body, as: UTF8.self) } == [expectedBody])
    }

    @Test("A request takes records while its body is at most the limit's bytes: at the limit it holds two, one byte under it one each")
    func byteBoundary() throws {
        // [null,null] is 11 bytes.
        let atLimit = try BatchLimit(maximumRecordCount: .max, maximumByteCount: 11, maximumRecordByteCount: .max)
        let underLimit = try BatchLimit(maximumRecordCount: .max, maximumByteCount: 10, maximumRecordByteCount: .max)
        let batch = (0 ..< 2).map { _ in EventRecord(event: Sized(size: 0), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil) }
        let expectedAtLimit = [2]
        let expectedUnderLimit = [1, 1]

        let actualAtLimit = atLimit.requests(for: batch, in: .array) { _ throws(Failure) in JSON.null } oversized: { Failure(reason: "\($0)") }
        let actualUnderLimit = underLimit.requests(for: batch, in: .array) { _ throws(Failure) in JSON.null } oversized: { Failure(reason: "\($0)") }

        #expect(actualAtLimit.requests.map(\.recordIDs.count) == expectedAtLimit)
        #expect(actualUnderLimit.requests.map(\.recordIDs.count) == expectedUnderLimit)
    }

    @Test("A record at the limit's bytes for one record is sent, and one byte over it is left out with its byte count")
    func recordByteBoundary() throws {
        let limit = try BatchLimit(maximumRecordCount: .max, maximumByteCount: .max, maximumRecordByteCount: 4)
        let fitting = EventRecord(event: Sized(size: 2), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)
        let over = EventRecord(event: Sized(size: 3), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)
        let expectedSkipped = [SkippedRecord(recordID: over.id, eventName: "sized", schemaVersion: 1, reason: Failure(reason: "5"))]

        let actual = limit.requests(for: [fitting, over], in: .array) { record throws(Failure) in
            .string(String(repeating: "x", count: (record.event as? Sized)?.size ?? 0))
        } oversized: { Failure(reason: "\($0)") }

        #expect(actual.requests.map(\.recordIDs) == [[fitting.id]])
        #expect(actual.skippedRecords == expectedSkipped)
    }

    @Test("A record too large for a request of it alone beside the envelope is left out, though under the limit for one record")
    func envelopeLeavesNoRoom() throws {
        // [null] is 6 bytes: a 5-byte limit leaves 3 bytes for a record, under null's 4.
        let limit = try BatchLimit(maximumRecordCount: .max, maximumByteCount: 5, maximumRecordByteCount: .max)
        let record = EventRecord(event: Sized(size: 0), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)
        let expectedSkipped = [SkippedRecord(recordID: record.id, eventName: "sized", schemaVersion: 1, reason: Failure(reason: "4"))]

        let actual = limit.requests(for: [record], in: .array) { _ throws(Failure) in JSON.null } oversized: { Failure(reason: "\($0)") }

        #expect(actual.requests.isEmpty)
        #expect(actual.skippedRecords == expectedSkipped)
    }

    @Test("Every record is left out when the envelope alone is over the request's limit")
    func envelopeOverLimit() throws {
        let limit = try BatchLimit(maximumRecordCount: .max, maximumByteCount: 1, maximumRecordByteCount: .max)
        let record = EventRecord(event: Sized(size: 0), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)

        let actual = limit.requests(for: [record], in: .array) { _ throws(Failure) in JSON.null } oversized: { Failure(reason: "\($0)") }

        #expect(actual.requests.isEmpty)
        #expect(actual.skippedRecords.map(\.recordID) == [record.id])
    }

    @Test("A request holds at most the limit's count: at a count of 1 every record is a request of its own")
    func countBoundary() throws {
        let limit = try BatchLimit(maximumRecordCount: 1, maximumByteCount: .max, maximumRecordByteCount: .max)
        let batch = (0 ..< 3).map { _ in EventRecord(event: Sized(size: 0), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil) }
        let expected = batch.map { [$0.id] }

        let actual = limit.requests(for: batch, in: .array) { _ throws(Failure) in JSON.null } oversized: { Failure(reason: "\($0)") }

        #expect(actual.requests.map(\.recordIDs) == expected)
    }

    @Test("For any batch and limit, the requests match a naive greedy split: in order, each within the limit, every record sent or left out once", .tags(.randomized))
    func greedyModel() async {
        // Each value is a record: -1 throws, and any other is a string of value / 5 repeats of the
        // letter value % 5, so multi-byte and escaped letters meet every boundary.
        await propertyCheck(count: 500, input: Gen.int(in: -1 ... 64).array(of: 0 ... 24), Gen.int(in: 1 ... 5), Gen.int(in: 1 ... 60), Gen.int(in: 1 ... 24)) { values, count, bytes, recordBytes in
            try check(values: values, count: count, bytes: bytes, recordBytes: recordBytes)
        }

        func check(values: [Int], count: Int, bytes: Int, recordBytes: Int) throws {
            let limit = try BatchLimit(maximumRecordCount: count, maximumByteCount: bytes, maximumRecordByteCount: recordBytes)
            let envelope = JSONEnvelope(["k": .integer(1)], arrayMember: "a")
            let batch = values.map { value in
                EventRecord(event: Sized(size: value < 0 ? -1 : value / 5, letter: max(value, 0) % 5), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)
            }

            // The naive reference: build each body as text, escaping by hand, and measure it.
            var expectedRequests: [[Int]] = []
            var expectedSkipped: [Int] = []
            var current: [Int] = []
            func element(_ index: Int) -> String {
                "\"" + String(repeating: Self.letters[max(values[index], 0) % 5].json, count: values[index] / 5) + "\""
            }
            func body(_ indices: [Int]) -> String {
                #"{"a":["# + indices.map(element).joined(separator: ",") + #"],"k":1}"#
            }
            for (index, value) in values.enumerated() {
                if value < 0 {
                    expectedSkipped.append(index)
                    continue
                }
                if element(index).utf8.count > recordBytes || body([index]).utf8.count > bytes {
                    expectedSkipped.append(index)
                    continue
                }
                if !current.isEmpty, current.count == count || body(current + [index]).utf8.count > bytes {
                    expectedRequests.append(current)
                    current = []
                }
                current.append(index)
            }
            if !current.isEmpty {
                expectedRequests.append(current)
            }

            let actual = limit.requests(for: batch, in: envelope) { record throws(Failure) in
                let sized = (record.event as? Sized) ?? Sized(size: 0)
                guard sized.size >= 0 else { throw Failure(reason: "negative") }
                return .string(String(repeating: Self.letters[sized.letter].text, count: sized.size))
            } oversized: { Failure(reason: "\($0)") }

            #expect(actual.requests.map(\.recordIDs) == expectedRequests.map { $0.map { batch[$0].id } })
            #expect(actual.requests.map { String(decoding: $0.body.body, as: UTF8.self) } == expectedRequests.map(body))
            #expect(actual.skippedRecords.map(\.recordID) == expectedSkipped.map { batch[$0].id })
        }
    }
}
