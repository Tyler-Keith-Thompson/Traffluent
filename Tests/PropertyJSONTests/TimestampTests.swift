import Foundation
import PropertyBased
import PropertyJSON
import Testing
import TraffluentTestSupport

@Suite("Date: ISO 8601 and epoch-millisecond timestamps")
struct TimestampTests {
    @Test("A hand-worked date is an ISO 8601 timestamp in UTC with milliseconds, and its milliseconds since 1970")
    func handWorked() throws {
        let sut = Date(timeIntervalSince1970: 1_795_442_607.5)
        let expectedISO = "2026-11-23T14:03:27.500Z"
        let expectedMilliseconds: Int64 = 1_795_442_607_500

        let actualISO = sut.iso8601Timestamp
        let actualMilliseconds = try sut.millisecondsSince1970()

        #expect(actualISO == expectedISO)
        #expect(actualMilliseconds == expectedMilliseconds)
    }

    @Test("The epoch is 1970-01-01T00:00:00.000Z and 0 milliseconds")
    func epoch() throws {
        let sut = Date(timeIntervalSince1970: 0)
        let expectedISO = "1970-01-01T00:00:00.000Z"
        let expectedMilliseconds: Int64 = 0

        let actualISO = sut.iso8601Timestamp
        let actualMilliseconds = try sut.millisecondsSince1970()

        #expect(actualISO == expectedISO)
        #expect(actualMilliseconds == expectedMilliseconds)
    }

    @Test("A fraction of a millisecond is rounded down, toward the past, before and after the epoch")
    func roundsDown() throws {
        let after = Date(timeIntervalSince1970: 0.0015)
        let before = Date(timeIntervalSince1970: -0.0015)
        let expectedAfter: Int64 = 1
        let expectedBefore: Int64 = -2
        let expectedAfterISO = "1970-01-01T00:00:00.001Z"

        let actualAfter = try after.millisecondsSince1970()
        let actualBefore = try before.millisecondsSince1970()
        let actualAfterISO = after.iso8601Timestamp

        #expect(actualAfter == expectedAfter)
        #expect(actualBefore == expectedBefore)
        #expect(actualAfterISO == expectedAfterISO)
    }

    @Test("millisecondsSince1970 throws UnrepresentableTimestamp at 2^63 milliseconds, and not one step of a Double below it")
    func upperBoundary() throws {
        let boundary: Double = 0x1p63 / 1000
        let throwing = Date(timeIntervalSince1970: boundary)
        let fitting = Date(timeIntervalSince1970: boundary.nextDown)
        let expected = Int64(exactly: (boundary.nextDown * 1000).rounded(.down))

        #expect(throws: UnrepresentableTimestamp()) {
            try throwing.millisecondsSince1970()
        }
        let actual = try fitting.millisecondsSince1970()
        #expect(actual == expected)
    }

    @Test("millisecondsSince1970 is Int64.min at -2^63 milliseconds, and throws UnrepresentableTimestamp one step of a Double below it")
    func lowerBoundary() throws {
        let boundary: Double = -0x1p63 / 1000
        let fitting = Date(timeIntervalSince1970: boundary)
        let throwing = Date(timeIntervalSince1970: boundary.nextDown)
        let expected = Int64.min

        let actual = try fitting.millisecondsSince1970()

        #expect(actual == expected)
        #expect(throws: UnrepresentableTimestamp()) {
            try throwing.millisecondsSince1970()
        }
    }

    @Test("millisecondsSince1970 throws UnrepresentableTimestamp for an infinite or NaN date", arguments: [Double.infinity, -Double.infinity, Double.nan])
    func notFinite(interval: Double) {
        let sut = Date(timeIntervalSince1970: interval)

        #expect(throws: UnrepresentableTimestamp()) {
            try sut.millisecondsSince1970()
        }
    }

    @Test("For any date, the ISO 8601 timestamp's milliseconds are the epoch milliseconds', so both name the same millisecond", .tags(.randomized))
    func formatsAgree() async {
        // Within 10^12 ms of the epoch (years 1938 to 2001), half a millisecond past a whole one, so
        // rounding down is unambiguous at a Double's precision.
        await propertyCheck(count: 500, input: Gen.int64(in: -1_000_000_000_000 ... 1_000_000_000_000)) { milliseconds in
            try check(milliseconds: milliseconds)
        }

        func check(milliseconds: Int64) throws {
            let sut = Date(timeIntervalSince1970: (Double(milliseconds) + 0.5) / 1000)
            let expected = milliseconds
            let expectedFraction = String(format: "%03lld", ((milliseconds % 1000) + 1000) % 1000)

            let actual = try sut.millisecondsSince1970()
            let actualFraction = String(sut.iso8601Timestamp.dropLast().suffix(3))

            #expect(actual == expected)
            #expect(actualFraction == expectedFraction)
        }
    }
}
