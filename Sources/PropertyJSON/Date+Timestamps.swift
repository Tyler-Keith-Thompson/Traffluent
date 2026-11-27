public import Foundation

extension Date {
    /// The date in ISO 8601, in UTC with milliseconds, rounded down: `2026-11-23T14:03:27.512Z`.
    ///
    /// The form a `Date` property is written in, and the timestamp most JSON ingestion APIs take.
    /// The date is counted in the proleptic Gregorian calendar, as ISO 8601 counts dates, before
    /// the calendar reform of October 1582 too: 62,135,596,800 seconds before 1970 is
    /// `0001-01-01T00:00:00.000Z`. Years from 1 to 9999 have four digits. Year 0, which is 1 BCE,
    /// is `0000`, an earlier year is negative (`-0001`), and a year after 9999 has as many digits
    /// as it needs. A date more than `Int64.max` milliseconds from 1970 is written as the nearest
    /// date that isn't, and NaN as the earliest.
    ///
    /// - Complexity: O(1).
    public var iso8601Timestamp: String {
        // Days and milliseconds rather than Foundation's formatters. ISO8601FormatStyle and
        // Date.FormatStyle count a date before 1582-10-15 in the Julian calendar (0001-01-01 comes
        // out as 0001-01-03), and Calendar has no public way to move its Gregorian change date.
        // DateFormatter's gregorianStartDate can, but it rounds to the nearest millisecond rather
        // than down, writes a year before 1 as a year of its era, and isn't Sendable.
        let milliseconds = (try? millisecondsSince1970()) ?? (timeIntervalSince1970 > 0 ? .max : .min)
        let (days, millisecondOfDay) = milliseconds.flooredQuotientAndRemainder(dividingBy: 86_400_000)
        let date = CivilDate(daysSince1970: days)
        var text: [UInt8] = []
        text.reserveCapacity(32)
        if date.year < 0 {
            text.append(UInt8(ascii: "-"))
        }
        text.appendDecimal(date.year.magnitude, digits: 4)
        text.append(UInt8(ascii: "-"))
        text.appendDecimal(date.month.magnitude, digits: 2)
        text.append(UInt8(ascii: "-"))
        text.appendDecimal(date.day.magnitude, digits: 2)
        text.append(UInt8(ascii: "T"))
        text.appendDecimal((millisecondOfDay / 3_600_000).magnitude, digits: 2)
        text.append(UInt8(ascii: ":"))
        text.appendDecimal((millisecondOfDay / 60_000 % 60).magnitude, digits: 2)
        text.append(UInt8(ascii: ":"))
        text.appendDecimal((millisecondOfDay / 1_000 % 60).magnitude, digits: 2)
        text.append(UInt8(ascii: "."))
        text.appendDecimal((millisecondOfDay % 1_000).magnitude, digits: 3)
        text.append(UInt8(ascii: "Z"))
        return String(decoding: text, as: UTF8.self)
    }

    /// The milliseconds from 1970-01-01T00:00:00Z to the date, rounded down, as
    /// ``iso8601Timestamp`` rounds: an epoch-milliseconds timestamp.
    ///
    /// - Returns: The whole milliseconds since 1970, negative before it.
    /// - Throws: ``UnrepresentableTimestamp`` when the date isn't finite, or is more than
    ///   `Int64.max` milliseconds from 1970 either way.
    public func millisecondsSince1970() throws(UnrepresentableTimestamp) -> Int64 {
        // Int64(exactly:) of the rounded-down value: nil for NaN, an infinity and anything outside
        // Int64's range, where Int64(_:) would trap.
        guard let milliseconds = Int64(exactly: (timeIntervalSince1970 * 1000).rounded(.down)) else {
            throw UnrepresentableTimestamp()
        }
        return milliseconds
    }
}

/// A day in the proleptic Gregorian calendar, by year, month and day of the month.
private struct CivilDate {
    /// The year, astronomically numbered: 0 is 1 BCE.
    var year: Int64
    /// The month, from 1 for January to 12.
    var month: Int64
    /// The day of the month, from 1.
    var day: Int64

    /// The day `days` after 1970-01-01, or before it when negative.
    ///
    /// Howard Hinnant's `civil_from_days`
    /// (https://howardhinnant.github.io/date_algorithms.html#civil_from_days), which counts years
    /// from March, so a leap day ends the year, in eras of 400 years, which repeat exactly. It is
    /// exact for every `days` from a millisecond count of `Int64`, about 292 million years either
    /// way.
    init(daysSince1970 days: Int64) {
        // Days since 0000-03-01, the start of an era.
        let shifted = days + 719_468
        let era = (shifted >= 0 ? shifted : shifted - 146_096) / 146_097
        let dayOfEra = shifted - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1_460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        // Months from March: 0 is March, 10 January and 11 February.
        let monthFromMarch = (5 * dayOfYear + 2) / 153
        day = dayOfYear - (153 * monthFromMarch + 2) / 5 + 1
        month = monthFromMarch < 10 ? monthFromMarch + 3 : monthFromMarch - 9
        year = yearOfEra + era * 400 + (month <= 2 ? 1 : 0)
    }
}

extension Int64 {
    /// The quotient rounded toward negative infinity, and the remainder, from 0 to less than
    /// `divisor`, that goes with it; `divisor` is positive.
    fileprivate func flooredQuotientAndRemainder(dividingBy divisor: Int64) -> (quotient: Int64, remainder: Int64) {
        let (quotient, remainder) = quotientAndRemainder(dividingBy: divisor)
        return remainder < 0 ? (quotient - 1, remainder + divisor) : (quotient, remainder)
    }
}

extension [UInt8] {
    /// Appends `value`'s decimal digits as ASCII, with zeros before them to make at least
    /// `digits` of them.
    fileprivate mutating func appendDecimal(_ value: UInt64, digits: Int) {
        var count = 1
        var rest = value / 10
        while rest > 0 {
            count += 1
            rest /= 10
        }
        append(contentsOf: repeatElement(UInt8(ascii: "0"), count: Swift.max(digits, count)))
        // The zeros written, the digits replace them from the end, so a 0 stays one zero.
        var remaining = value
        var index = endIndex
        while remaining > 0 {
            index -= 1
            self[index] = UInt8(ascii: "0") + UInt8(remaining % 10)
            remaining /= 10
        }
    }
}
