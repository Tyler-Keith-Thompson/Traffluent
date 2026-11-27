import Foundation
import HTTPDestinations
import PropertyJSON
import Testing
import TrackingPlans

@Suite("BatchLimit and JSONEnvelope")
struct BatchLimitTests {
    @Test("The initializer throws InvalidBatchLimit when any of the three limits is 0", arguments: [(0, 1, 1), (1, 0, 1), (1, 1, 0), (-1, 1, 1), (Int.min, Int.min, Int.min)])
    func invalid(count: Int, bytes: Int, recordBytes: Int) {
        #expect(throws: InvalidBatchLimit()) {
            try BatchLimit(maximumRecordCount: count, maximumByteCount: bytes, maximumRecordByteCount: recordBytes)
        }
    }

    @Test("The initializer accepts 1 for every limit, the least that holds a record")
    func least() throws {
        let expected = 1

        let actual = try BatchLimit(maximumRecordCount: 1, maximumByteCount: 1, maximumRecordByteCount: 1)

        #expect(actual.maximumRecordCount == expected)
        #expect(actual.maximumByteCount == expected)
        #expect(actual.maximumRecordByteCount == expected)
    }

    @Test("unlimited has no limit on the count, the bytes or one record's bytes")
    func unlimited() {
        let expected = Int.max

        let actual = BatchLimit.unlimited

        #expect(actual.maximumRecordCount == expected)
        #expect(actual.maximumByteCount == expected)
        #expect(actual.maximumRecordByteCount == expected)
    }

    @Test("An envelope's body is what JSON.minified writes for the object with the elements as its array, members sorted around it")
    func envelopeMatchesMinified() throws {
        let members: [String: JSON] = ["api_key": .string("k"), "schema": .integer(2), "z": .null]
        let elements: [JSON] = [.object(["a": .integer(1)]), .string("b")]
        let sut = JSONEnvelope(members, arrayMember: "batch")
        var whole = members
        whole["batch"] = .array(elements)
        let expected = JSON.object(whole).minified
        let expectedContentType = "application/json"

        let actual = sut.body(of: elements.map(\.minified))

        #expect(String(decoding: actual.body, as: UTF8.self) == expected)
        #expect(actual.contentType == expectedContentType)
        #expect(sut.byteCount == expected.utf8.count - elements.map(\.minified.utf8.count).reduce(0, +) - 1)
    }

    @Test("An envelope's member of the array's name is replaced by the array")
    func envelopeReplacesArrayMember() {
        let sut = JSONEnvelope(["batch": .string("dropped"), "a": .boolean(true)], arrayMember: "batch")
        let expected = #"{"a":true,"batch":[1]}"#

        let actual = sut.body(of: ["1"])

        #expect(String(decoding: actual.body, as: UTF8.self) == expected)
    }

    @Test("The array envelope is a bare array of two bytes, and of no elements is []")
    func arrayEnvelope() {
        let expectedEmpty = "[]"
        let expected = "[1,2]"
        let expectedByteCount = 2

        let actualEmpty = JSONEnvelope.array.body(of: [])
        let actual = JSONEnvelope.array.body(of: ["1", "2"])

        #expect(String(decoding: actualEmpty.body, as: UTF8.self) == expectedEmpty)
        #expect(String(decoding: actual.body, as: UTF8.self) == expected)
        #expect(JSONEnvelope.array.byteCount == expectedByteCount)
    }
}
