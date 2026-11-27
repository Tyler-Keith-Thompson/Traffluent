import EventMacros
import Foundation
import HTTPDestinations
import JSONValues
import PropertyBased
import PropertyJSON
import Testing
import TraffluentTestSupport

@Suite("BatchLimit.requests(for:in:maximumAge:encoding:oversized:)")
struct BatchDeadlineTests {
    @Event(name: "aged")
    struct Aged {
        var fails: Bool = false
    }

    struct Failure: Error, Hashable {
        var reason: String
    }

    @Test("Each request's deadline is the maximum age after its earliest record, whatever their order, counting only the records it holds")
    func handWorked() throws {
        // Two records a request: the first holds the records of 10 and 5 (the one of 0 is left
        // out), the second those of 20 and 30, so its deadline isn't carried from the first.
        let limit = try BatchLimit(maximumRecordCount: 2, maximumByteCount: .max, maximumRecordByteCount: .max)
        let records: [(seconds: TimeInterval, fails: Bool)] = [(10, false), (0, true), (5, false), (20, false), (30, false)]
        let batch = records.map { EventRecord(event: Aged(fails: $0.fails), timestamp: Date(timeIntervalSince1970: $0.seconds), sourceLocation: nil) }
        let maximumAge: Duration = .seconds(100)
        let expectedIDs = [[batch[0].id, batch[2].id], [batch[3].id, batch[4].id]]
        let expectedDeadlines: [Date?] = [Date(timeIntervalSince1970: 105), Date(timeIntervalSince1970: 120)]

        let actual = try limit.requests(for: batch, in: .array, maximumAge: maximumAge) { record throws(Failure) in
            guard (record.event as? Aged)?.fails != true else { throw Failure(reason: "fails") }
            return .null
        } oversized: { Failure(reason: "\($0)") }

        #expect(actual.requests.map(\.recordIDs) == expectedIDs)
        #expect(actual.requests.map(\.deadline) == expectedDeadlines)
    }

    @Test("A maximum age's fraction of a second carries into the deadline")
    func fractionalMaximumAge() throws {
        let batch = [EventRecord(event: Aged(), timestamp: Date(timeIntervalSince1970: 10), sourceLocation: nil)]
        let maximumAge: Duration = .milliseconds(1_500)
        let expected: [Date?] = [Date(timeIntervalSince1970: 11.5)]

        let actual = try BatchLimit.unlimited.requests(for: batch, in: .array, maximumAge: maximumAge) { _ throws(Failure) in JSON.null } oversized: { Failure(reason: "\($0)") }

        #expect(actual.requests.map(\.deadline) == expected)
    }

    @Test("Without a maximum age, no request has a deadline")
    func noMaximumAge() throws {
        let limit = try BatchLimit(maximumRecordCount: 1, maximumByteCount: .max, maximumRecordByteCount: .max)
        let batch = [0, 1].map { EventRecord(event: Aged(), timestamp: Date(timeIntervalSince1970: $0), sourceLocation: nil) }
        let expected: [Date?] = [nil, nil]

        let actual = limit.requests(for: batch, in: .array) { _ throws(Failure) in JSON.null } oversized: { Failure(reason: "\($0)") }

        #expect(actual.requests.map(\.deadline) == expected)
    }

    @Test("A maximum age of 0 is accepted, and makes the earliest record's time the deadline")
    func zeroMaximumAge() throws {
        let batch = [EventRecord(event: Aged(), timestamp: Date(timeIntervalSince1970: 7), sourceLocation: nil)]
        let maximumAge: Duration = .zero
        let expected: [Date?] = [Date(timeIntervalSince1970: 7)]

        let actual = try BatchLimit.unlimited.requests(for: batch, in: .array, maximumAge: maximumAge) { _ throws(Failure) in JSON.null } oversized: { Failure(reason: "\($0)") }

        #expect(actual.requests.map(\.deadline) == expected)
    }

    @Test("A maximum age of one attosecond below zero throws NegativeMaximumAge")
    func negativeMaximumAge() {
        let batch = [EventRecord(event: Aged(), timestamp: Date(timeIntervalSince1970: 7), sourceLocation: nil)]
        let maximumAge: Duration = .zero - Duration(secondsComponent: 0, attosecondsComponent: 1)

        #expect(throws: NegativeMaximumAge()) {
            try BatchLimit.unlimited.requests(for: batch, in: .array, maximumAge: maximumAge) { _ throws(Failure) in JSON.null } oversized: { Failure(reason: "\($0)") }
        }
    }

    @Test("A record whose timestamp is NaN or infinite makes its request's deadline NaN, whether it comes first, between or last", arguments: [Double.nan, .infinity, -.infinity], [0, 1, 2])
    func nonFiniteTimestamp(timestamp: Double, position: Int) throws {
        var seconds: [TimeInterval] = [10, 20]
        seconds.insert(timestamp, at: position)
        let batch = seconds.map { EventRecord(event: Aged(), timestamp: Date(timeIntervalSince1970: $0), sourceLocation: nil) }
        let maximumAge: Duration = .seconds(100)

        let actual = try BatchLimit.unlimited.requests(for: batch, in: .array, maximumAge: maximumAge) { _ throws(Failure) in JSON.null } oversized: { Failure(reason: "\($0)") }

        let request = try #require(actual.requests.first)
        let deadline = try #require(request.deadline)
        #expect(deadline.timeIntervalSinceReferenceDate.isNaN)
    }

    @Test("A NaN timestamp in one request leaves the next request's deadline its own")
    func nonFiniteTimestampNotCarried() throws {
        let limit = try BatchLimit(maximumRecordCount: 1, maximumByteCount: .max, maximumRecordByteCount: .max)
        let batch = [TimeInterval.nan, 20].map { EventRecord(event: Aged(), timestamp: Date(timeIntervalSince1970: $0), sourceLocation: nil) }
        let maximumAge: Duration = .seconds(100)
        let expected: Date? = Date(timeIntervalSince1970: 120)

        let actual = try limit.requests(for: batch, in: .array, maximumAge: maximumAge) { _ throws(Failure) in JSON.null } oversized: { Failure(reason: "\($0)") }

        #expect(actual.requests.last?.deadline == expected)
    }

    @Test("For any batch, limit and maximum age, each request's deadline is the age after the earliest of its records' timestamps, or NaN when one isn't finite", .tags(.randomized))
    func earliestModel() async {
        await propertyCheck(count: 300, input: Gen.int(in: -2 ... 1_000).array(of: 0 ... 24), Gen.int(in: 1 ... 5), Gen.int(in: 0 ... 1_000)) { values, count, age in
            try check(values: values, count: count, age: age)
        }

        func check(values: [Int], count: Int, age: Int) throws {
            // A value of -1 is a record that throws, -2 one whose timestamp is NaN; any other is
            // its timestamp in seconds.
            let limit = try BatchLimit(maximumRecordCount: count, maximumByteCount: .max, maximumRecordByteCount: .max)
            let batch = values.map { EventRecord(event: Aged(fails: $0 == -1), timestamp: Date(timeIntervalSince1970: $0 == -2 ? .nan : TimeInterval($0)), sourceLocation: nil) }
            let timestamps = Dictionary(uniqueKeysWithValues: batch.map { ($0.id, $0.timestamp.timeIntervalSince1970) })

            let actual = try limit.requests(for: batch, in: .array, maximumAge: .seconds(age)) { record throws(Failure) in
                guard (record.event as? Aged)?.fails != true else { throw Failure(reason: "fails") }
                return .null
            } oversized: { Failure(reason: "\($0)") }

            // The naive reference: NaN when any timestamp of the identifiers a request names is
            // NaN, else the smallest of them, plus the age.
            let expected = actual.requests.map { request in
                let seconds = request.recordIDs.compactMap { timestamps[$0] }
                return seconds.contains(where: \.isNaN) ? .nan : seconds.min().map { $0 + TimeInterval(age) } ?? .nan
            }
            let actualSeconds = actual.requests.map { $0.deadline?.timeIntervalSince1970 ?? -.infinity }
            #expect(actualSeconds.count == expected.count)
            for (actual, expected) in zip(actualSeconds, expected) {
                #expect(actual == expected || actual.isNaN && expected.isNaN)
            }
        }
    }
}
