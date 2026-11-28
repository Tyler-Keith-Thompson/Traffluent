import Foundation
import Generators
import PropertyBased
import PropertyJSON
import Sampling
import Testing
import TraffluentTestSupport

@Suite("Date: ISO 8601 and epoch-millisecond timestamps")
struct TimestampTests {
    @Test("A hand-worked date is an ISO 8601 timestamp in UTC with milliseconds, and its milliseconds since 1970")
    func handWorked() throws {
        let sut = Date(timeIntervalSince1970: 1_795_442_607.5)
        let expectedISO = "2026-11-23T14:03:27.500Z"
        let expectedMilliseconds: Int64 = 1_795_442_607_500

        let actualISO = try sut.iso8601Timestamp
        let actualMilliseconds = try sut.millisecondsSince1970()

        #expect(actualISO == expectedISO)
        #expect(actualMilliseconds == expectedMilliseconds)
    }

    @Test("The epoch is 1970-01-01T00:00:00.000Z and 0 milliseconds")
    func epoch() throws {
        let sut = Date(timeIntervalSince1970: 0)
        let expectedISO = "1970-01-01T00:00:00.000Z"
        let expectedMilliseconds: Int64 = 0

        let actualISO = try sut.iso8601Timestamp
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
        let actualAfterISO = try after.iso8601Timestamp

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
            let actualFraction = String(try sut.iso8601Timestamp.dropLast().suffix(3))

            #expect(actual == expected)
            #expect(actualFraction == expectedFraction)
        }
    }

    @Test("0001-01-01T00:00:00Z, 62,135,596,800 seconds before 1970, is 0001-01-01T00:00:00.000Z, in the proleptic Gregorian calendar")
    func yearOne() throws {
        let sut = Date(timeIntervalSince1970: -62_135_596_800)
        let expected = "0001-01-01T00:00:00.000Z"

        let actual = try sut.iso8601Timestamp

        #expect(actual == expected)
    }

    @Test("The days either side of the Gregorian reform, 1582-10-14 and 1582-10-15, are one day apart, not eleven", arguments: [
        (-12_219_379_200.0, "1582-10-14T00:00:00.000Z"), (-12_219_292_800, "1582-10-15T00:00:00.000Z"),
    ])
    func reform(seconds: Double, expected: String) throws {
        let sut = Date(timeIntervalSince1970: seconds)

        let actual = try sut.iso8601Timestamp

        #expect(actual == expected)
    }

    @Test("Leap days follow the Gregorian rule before the reform too: 1500 has no February 29, 0004 and 2000 have one, 1900 none", arguments: [
        (-14_826_758_400.0, "1500-02-28T00:00:00.000Z"), (-14_826_672_000, "1500-03-01T00:00:00.000Z"),
        (-62_035_891_200, "0004-02-29T00:00:00.000Z"), (951_782_400, "2000-02-29T00:00:00.000Z"),
        (-2_203_891_200.5, "1900-02-28T23:59:59.500Z"), (-2_203_891_200, "1900-03-01T00:00:00.000Z"),
    ])
    func leapDays(seconds: Double, expected: String) throws {
        let sut = Date(timeIntervalSince1970: seconds)

        let actual = try sut.iso8601Timestamp

        #expect(actual == expected)
    }

    @Test("Outside the four-digit years, year 0 is 0000, an earlier year is negative, and a later one has five digits", arguments: [
        (-62_135_596_800.001, "0000-12-31T23:59:59.999Z"), (-62_167_219_200, "0000-01-01T00:00:00.000Z"),
        (-62_198_755_200, "-0001-01-01T00:00:00.000Z"), (-377_705_116_800, "-9999-01-01T00:00:00.000Z"),
        (253_402_300_799.5, "9999-12-31T23:59:59.500Z"), (253_402_300_800, "10000-01-01T00:00:00.000Z"),
    ])
    func beyondFourDigits(seconds: Double, expected: String) throws {
        let sut = Date(timeIntervalSince1970: seconds)

        let actual = try sut.iso8601Timestamp

        #expect(actual == expected)
    }

    @Test("iso8601Timestamp throws UnrepresentableTimestamp at 2^63 milliseconds, and not one step of a Double below it")
    func timestampUpperBoundary() throws {
        let boundary: Double = 0x1p63 / 1000
        let throwing = Date(timeIntervalSince1970: boundary)
        let fitting = Date(timeIntervalSince1970: boundary.nextDown)
        let expected = "292278994-08-17T07:12:53.760Z"

        #expect(throws: UnrepresentableTimestamp()) {
            try throwing.iso8601Timestamp
        }
        let actual = try fitting.iso8601Timestamp
        #expect(actual == expected)
    }

    @Test("iso8601Timestamp is Int64.min milliseconds' date at -2^63 milliseconds, and throws UnrepresentableTimestamp one step of a Double below it")
    func timestampLowerBoundary() throws {
        let boundary: Double = -0x1p63 / 1000
        let fitting = Date(timeIntervalSince1970: boundary)
        let throwing = Date(timeIntervalSince1970: boundary.nextDown)
        let expected = "-292275055-05-16T16:47:04.192Z"

        let actual = try fitting.iso8601Timestamp

        #expect(actual == expected)
        #expect(throws: UnrepresentableTimestamp()) {
            try throwing.iso8601Timestamp
        }
    }

    @Test("iso8601Timestamp throws UnrepresentableTimestamp for an infinite or NaN date", arguments: [Double.infinity, -Double.infinity, Double.nan])
    func timestampNotFinite(interval: Double) {
        let sut = Date(timeIntervalSince1970: interval)

        #expect(throws: UnrepresentableTimestamp()) {
            try sut.iso8601Timestamp
        }
    }

    @Test("For any day and time from year -9999 to 19999, the ISO 8601 timestamp is the proleptic Gregorian date a naive count of days gives", .tags(.randomized))
    func prolepticGregorian() async {
        await propertyCheck(count: 500, input: Gen.uint64(in: .min ... .max)) { seed in
            try check(seed: seed)
        }

        // Howard Hinnant's days_from_civil
        // (https://howardhinnant.github.io/date_algorithms.html#days_from_civil): the days from
        // 1970-01-01 to a proleptic Gregorian date, counting years from March in 400-year eras.
        func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
            let marchYear = month <= 2 ? year - 1 : year
            let era = (marchYear >= 0 ? marchYear : marchYear - 399) / 400
            let yearOfEra = marchYear - era * 400
            let dayOfYear = (153 * (month > 2 ? month - 3 : month + 9) + 2) / 5 + day - 1
            let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
            return era * 146_097 + dayOfEra - 719_468
        }

        func daysInMonth(_ month: Int, of year: Int) -> Int {
            let isLeap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
            return [31, isLeap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1]
        }

        func check(seed: UInt64) throws {
            var random = Xoshiro256StarStar(seed: seed)
            let year = random.integer(in: -9_999 ... 19_999)
            let month = random.integer(in: 1 ... 12)
            let day = random.integer(in: 1 ... daysInMonth(month, of: year))
            let millisecond = random.integer(in: 0 ... 86_399_999)
            // Half a millisecond past a whole one, so rounding down is unambiguous at a Double's
            // precision: within 2^49 milliseconds of 1970, a Double's step is under 0.1 ms.
            let milliseconds = Double(daysFromCivil(year: year, month: month, day: day)) * 86_400_000 + Double(millisecond) + 0.5
            let sut = Date(timeIntervalSince1970: milliseconds / 1000)
            let expectedYear = (year < 0 ? "-" : "") + String(format: "%04ld", abs(year))
            let expected = expectedYear + String(format: "-%02ld-%02ldT%02ld:%02ld:%02ld.%03ldZ", month, day, millisecond / 3_600_000, millisecond / 60_000 % 60, millisecond / 1_000 % 60, millisecond % 1_000)

            let actual = try sut.iso8601Timestamp

            #expect(actual == expected)
        }
    }

    @Test("Any millisecond's timestamp parses back as a date in that millisecond", .tags(.randomized))
    func parsesBack() async {
        await propertyCheck(count: 500, input: Gen.uint64(in: .min ... .max)) { seed in
            try check(seed: seed)
        }

        func check(seed: UInt64) throws {
            var random = Xoshiro256StarStar(seed: seed)
            // Half a millisecond past a whole one, so rounding down is unambiguous: within 2^49
            // milliseconds of 1970, a Double's step is under 0.1 ms.
            let expected = Int64(random.integer(in: -562_949_953_421_312 ... 562_949_953_421_312))
            let timestamp = try Date(timeIntervalSince1970: (Double(expected) + 0.5) / 1000).iso8601Timestamp

            let actual = try Date(iso8601Timestamp: timestamp)?.millisecondsSince1970()

            #expect(actual == expected)
        }
    }

    @Test("For any millisecond within 2^53 of 1970, the timestamp parses back as a date of exactly that millisecond, which some Date always reaches", .tags(.randomized))
    func parsesEveryMillisecond() async {
        await propertyCheck(count: 1000, input: Gen.int64(in: -9_007_199_254_740_992 ... 9_007_199_254_740_992)) { milliseconds in
            try check(milliseconds)
        }

        // Howard Hinnant's civil_from_days
        // (https://howardhinnant.github.io/date_algorithms.html#civil_from_days), written apart
        // from the library's, to spell the millisecond's timestamp without a Date.
        func timestamp(of milliseconds: Int64) -> String {
            let days = milliseconds >= 0 ? milliseconds / 86_400_000 : (milliseconds - 86_399_999) / 86_400_000
            let millisecond = milliseconds - days * 86_400_000
            let shifted = days + 719_468
            let era = (shifted >= 0 ? shifted : shifted - 146_096) / 146_097
            let dayOfEra = shifted - era * 146_097
            let yearOfEra = (dayOfEra - dayOfEra / 1_460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
            let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
            let monthFromMarch = (5 * dayOfYear + 2) / 153
            let day = dayOfYear - (153 * monthFromMarch + 2) / 5 + 1
            let month = monthFromMarch < 10 ? monthFromMarch + 3 : monthFromMarch - 9
            let year = yearOfEra + era * 400 + (month <= 2 ? 1 : 0)
            let yearText = (year < 0 ? "-" : "") + String(format: "%04lld", abs(year))
            return yearText + String(format: "-%02lld-%02lldT%02lld:%02lld:%02lld.%03lldZ", month, day, millisecond / 3_600_000, millisecond / 60_000 % 60, millisecond / 1_000 % 60, millisecond % 1_000)
        }

        func check(_ expected: Int64) throws {
            // Whether a Date reaches the millisecond: a few Doubles of seconds since 1970 nearest its
            // start, and of seconds since 2001, rounded down as the timestamp rounds. Past 2^53 ms
            // from 1970 a step of a Double is over a millisecond apart, so some milliseconds are
            // reached by none.
            func around(_ start: Double) -> [Double] {
                [start.nextDown.nextDown, start.nextDown, start, start.nextUp, start.nextUp.nextUp]
            }
            let since1970 = around(Double(expected) / 1000).map { Date(timeIntervalSince1970: $0) }
            let sinceReference = around(Double(expected) / 1000 - Date.timeIntervalBetween1970AndReferenceDate).map { Date(timeIntervalSinceReferenceDate: $0) }
            let reached = (since1970 + sinceReference).contains { (try? $0.millisecondsSince1970()) == expected }

            let actual = Date(iso8601Timestamp: timestamp(of: expected))

            if let actual {
                #expect(try actual.millisecondsSince1970() == expected)
            }
            #expect(actual != nil || !reached)
        }
    }

    @Test("A millisecond whose nearest Date rounds into a later one parses back as the Date below it that rounds into it")
    func nearestAbove() throws {
        // -9007175353700285 ms from 1970: the Double nearest its start, -9008153660900.283 s from
        // 2001, rounds down to -9007175353700283 ms; the Double below it to this millisecond.
        let expected = Date(timeIntervalSinceReferenceDate: -9_008_153_660_900.285)
        let expectedMilliseconds: Int64 = -9_007_175_353_700_285
        let timestamp = try expected.iso8601Timestamp

        let actual = try #require(Date(iso8601Timestamp: timestamp))

        #expect(try expected.millisecondsSince1970() == expectedMilliseconds)
        #expect(try actual.millisecondsSince1970() == expectedMilliseconds)
    }

    @Test(
        "A timestamp parses back only in the form iso8601Timestamp writes",
        arguments: [
            ("1970-01-01T00:00:00.000Z", 0 as Int64?),
            ("0000-03-01T00:00:00.000Z", -62_162_035_200_000),
            ("10000-01-01T00:00:00.000Z", 253_402_300_800_000),
            ("1970-01-01T00:00:00Z", nil),
            ("00000-01-01T00:00:00.000Z", nil),
            ("-0000-01-01T00:00:00.000Z", nil),
            ("2023-02-29T00:00:00.000Z", nil),
        ]
    )
    func parsing(timestamp: String, expected: Int64?) throws {
        let actual = try Date(iso8601Timestamp: timestamp)?.millisecondsSince1970()

        #expect(actual == expected)
    }
}
