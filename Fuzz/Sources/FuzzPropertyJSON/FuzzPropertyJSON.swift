// BatchLimit's split of a batch into requests against a naive greedy model: a sequence of choices
// makes batches of records whose JSON is a string of 0 to 12 repeats of a letter (x, é, an emoji,
// a quote or a backslash, so one to four bytes and escapes), or an encoding that throws, a
// limit of 1 to 5 records, 1 to 60 bytes and 1 to 24 bytes a record, and a bare array or an object
// envelope. After every batch the requests are the model's, in order, each body the model's text
// within the limit, and each record left out is the model's, in order, with its reason. The
// limits are small, so records at a boundary, and envelopes that leave no room, are common.

import Events
import Foundation
import FuzzSupport
import HTTPDestinations
import JSONValues
import PropertyJSON

struct Sized: Event {
    var size: Int
    var letter: Int
}

/// Each letter a record's string repeats, and how JSON writes it, escaped by hand.
let letters: [(text: String, json: String)] = [("x", "x"), ("é", "é"), ("😀", "😀"), ("\"", #"\""#), ("\\", #"\\"#)]

struct Failure: Error, Equatable {
    var reason: String
}

/// The bodies and left-out records a greedy split should make, built as text and measured.
func model(sizes: [Int], letterIndices: [Int], count: Int, bytes: Int, recordBytes: Int, wrap: (String) -> String) -> (requests: [[Int]], bodies: [String], skipped: [(index: Int, reason: String)]) {
    func element(_ index: Int) -> String { "\"" + String(repeating: letters[letterIndices[index]].json, count: sizes[index]) + "\"" }
    func body(_ indices: [Int]) -> String { wrap(indices.map(element).joined(separator: ",")) }
    var requests: [[Int]] = []
    var skipped: [(index: Int, reason: String)] = []
    var current: [Int] = []
    for (index, size) in sizes.enumerated() {
        if size < 0 {
            skipped.append((index, "negative"))
            continue
        }
        if element(index).utf8.count > recordBytes || body([index]).utf8.count > bytes {
            skipped.append((index, "oversized \(element(index).utf8.count)"))
            continue
        }
        if !current.isEmpty, current.count == count || body(current + [index]).utf8.count > bytes {
            requests.append(current)
            current = []
        }
        current.append(index)
    }
    if !current.isEmpty {
        requests.append(current)
    }
    return (requests, requests.map(body), skipped)
}

@main
enum FuzzPropertyJSON {
    static func main() {
        runFuzzer { input in
            while !input.isEmpty {
                let count = input.int(in: 1 ... 5)
                let bytes = input.int(in: 1 ... 60)
                let recordBytes = input.int(in: 1 ... 24)
                guard let limit = try? BatchLimit(maximumRecordCount: count, maximumByteCount: bytes, maximumRecordByteCount: recordBytes) else {
                    check(false, "BatchLimit refused \(count), \(bytes), \(recordBytes)")
                    return
                }
                let copy = limit
                let isArray = input.int(below: 2) == 0
                let envelope = isArray ? JSONEnvelope.array : JSONEnvelope(["k": .integer(1)], arrayMember: "a")
                let wrap: (String) -> String = isArray ? { "[" + $0 + "]" } : { #"{"a":["# + $0 + #"],"k":1}"# }
                let recordCount = input.int(in: 0 ... 12)
                let sizes = (0 ..< recordCount).map { _ in input.int(in: -1 ... 12) }
                let letterIndices = (0 ..< recordCount).map { _ in input.int(below: letters.count) }
                let batch = zip(sizes, letterIndices).map { EventRecord(event: Sized(size: $0, letter: $1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil) }

                let actual = limit.requests(for: batch, in: envelope) { record throws(Failure) in
                    let sized = (record.event as? Sized) ?? Sized(size: 0, letter: 0)
                    guard sized.size >= 0 else { throw Failure(reason: "negative") }
                    return .string(String(repeating: letters[sized.letter].text, count: sized.size))
                } oversized: { Failure(reason: "oversized \($0)") }

                let expected = model(sizes: sizes, letterIndices: letterIndices, count: count, bytes: bytes, recordBytes: recordBytes, wrap: wrap)
                let actualIDs = actual.requests.map(\.recordIDs)
                let expectedIDs = expected.requests.map { $0.map { batch[$0].id } }
                check(actualIDs == expectedIDs, "sizes \(sizes) under \(count), \(bytes), \(recordBytes): requests of \(actual.requests.map { $0.recordIDs.count }), model \(expected.requests.map(\.count))")
                let actualBodies = actual.requests.map { String(decoding: $0.body.body, as: UTF8.self) }
                check(actualBodies == expected.bodies, "bodies \(actualBodies), model \(expected.bodies)")
                check(actualBodies.allSatisfy { $0.utf8.count <= bytes }, "a body over \(bytes) bytes: \(actualBodies)")
                let actualSkipped = actual.skippedRecords.map { "\($0.recordID) \($0.reason.reason)" }
                let expectedSkipped = expected.skipped.map { "\(batch[$0.index].id) \($0.reason)" }
                check(actualSkipped == expectedSkipped, "skipped \(actualSkipped), model \(expectedSkipped)")
                check(copy == limit, "the limit changed while splitting")
            }
        }
    }
}
