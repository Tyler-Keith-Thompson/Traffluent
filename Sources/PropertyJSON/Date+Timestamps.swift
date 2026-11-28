public import Foundation

extension Date {
    /// The date in ISO 8601, in UTC with milliseconds, rounded down: `2026-11-23T14:03:27.512Z`.
    ///
    /// The form a `Date` property is written in, and the timestamp most JSON ingestion APIs take.
    /// The date is counted in the proleptic Gregorian calendar, as ISO 8601 counts dates, before
    /// the calendar reform of October 1582 too: 62,135,596,800 seconds before 1970 is
    /// `0001-01-01T00:00:00.000Z`. Years from 1 to 9999 have four digits. Year 0, which is 1 BCE,
    /// is `0000`, an earlier year is negative (`-0001`), and a year after 9999 has as many digits
    /// as it needs.
    ///
    /// - Throws: ``UnrepresentableTimestamp`` when the date isn't finite, or is more than
    ///   `Int64.max` milliseconds from 1970 either way, as ``millisecondsSince1970()`` does.
    /// - Complexity: O(1).
    public var iso8601Timestamp: String {
        get throws(UnrepresentableTimestamp) {
            // Days and milliseconds rather than Foundation's formatters. ISO8601FormatStyle and
            // Date.FormatStyle count a date before 1582-10-15 in the Julian calendar (0001-01-01
            // comes out as 0001-01-03), and Calendar has no public way to move its Gregorian
            // change date. DateFormatter's gregorianStartDate can, but it rounds to the nearest
            // millisecond rather than down, writes a year before 1 as a year of its era, and
            // isn't Sendable.
            let milliseconds = try millisecondsSince1970()
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
    }

    /// The date an ISO 8601 timestamp of ``iso8601Timestamp``'s form names, or `nil` for text of
    /// any other form, or a day or time that doesn't exist.
    ///
    /// The form is exact: a year of four digits, or more with no leading zero, after a `-` when it
    /// is before year 0; then `-MM-DDTHH:MM:SS.mmmZ`. The date is the `Date` nearest the start of the
    /// millisecond when that is in the millisecond, else the first `Date` that is, so its timestamp is
    /// `text` again; `nil` when no `Date` is in it, as for some past 2^53 milliseconds from 1970.
    ///
    /// - Parameter text: A timestamp, such as `2026-11-23T14:03:27.512Z`.
    /// - Complexity: O(*n*) in the text's length.
    package init?(iso8601Timestamp text: String) {
        guard let milliseconds = Int64(iso8601Timestamp: Array(text.utf8)) else { return nil }
        // Date holds seconds since 2001 as a Double, which may not hold a millisecond's start
        // exactly, and millisecondsSince1970() rounds down from seconds since 1970, a Double whose
        // step can be far coarser (near 2001, by 2^40 and more). So stepping one Double at a time
        // can take too long. The Double nearest the start, from one rounding of the exact count
        // since 2001, is kept when it lands in the millisecond. Otherwise a bisection beside it
        // finds the first Double that does, as the rounding is monotonic. A
        // millisecond count no Double reaches, past about 2^53 of them, has no date.
        let sinceReference = Int128(milliseconds) - Int128(Self.millisecondsBetween1970AndReferenceDate)
        let nearest = Double(sinceReference) / 1000
        guard let actual = Self.milliseconds(atReferenceSeconds: nearest) else { return nil }
        guard actual != milliseconds else {
            self = Date(timeIntervalSinceReferenceDate: nearest)
            return
        }
        // Below: ms(low) < milliseconds <= ms(high), narrowed until they are adjacent Doubles. The
        // bracket spans two milliseconds, or two Doubles where a step is longer than one.
        let width = Swift.max(0.002, 2 * nearest.ulp)
        var low = actual < milliseconds ? nearest : nearest - width
        var high = actual < milliseconds ? nearest + width : nearest
        guard let lowest = Self.milliseconds(atReferenceSeconds: low), lowest < milliseconds,
              let highest = Self.milliseconds(atReferenceSeconds: high), highest >= milliseconds
        else { return nil }
        while low.nextUp < high {
            let middle = low + (high - low) / 2
            guard middle > low, middle < high, let reached = Self.milliseconds(atReferenceSeconds: middle) else { break }
            if reached < milliseconds {
                low = middle
            } else {
                high = middle
            }
        }
        guard Self.milliseconds(atReferenceSeconds: high) == milliseconds else { return nil }
        self = Date(timeIntervalSinceReferenceDate: high)
    }

    /// The milliseconds from 1970 to 2001-01-01T00:00:00Z, the reference date.
    private static let millisecondsBetween1970AndReferenceDate: Int64 = 978_307_200_000

    /// ``millisecondsSince1970()`` of the date `seconds` after the reference date, or nil where it
    /// throws.
    private static func milliseconds(atReferenceSeconds seconds: Double) -> Int64? {
        try? Date(timeIntervalSinceReferenceDate: seconds).millisecondsSince1970()
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

    /// The day `day` of month `month` of `year`, which may not exist.
    init(year: Int64, month: Int64, day: Int64) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The days from 1970-01-01 to this day, negative before it.
    ///
    /// Howard Hinnant's `days_from_civil`
    /// (https://howardhinnant.github.io/date_algorithms.html#days_from_civil), the inverse of
    /// ``init(daysSince1970:)``, exact for a year of up to 12 digits.
    var daysSince1970: Int64 {
        let marchYear = month <= 2 ? year - 1 : year
        let era = (marchYear >= 0 ? marchYear : marchYear - 399) / 400
        let yearOfEra = marchYear - era * 400
        let dayOfYear = (153 * (month > 2 ? month - 3 : month + 9) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    /// The days in the month, from 28 to 31.
    var daysInMonth: Int64 {
        switch month {
        case 2: year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }
}

extension Int64 {
    /// The milliseconds since 1970 of a timestamp of `Date/iso8601Timestamp`'s form, or `nil` for
    /// bytes of another form, a day or time that doesn't exist, or a count past `Int64`.
    fileprivate init?(iso8601Timestamp text: [UInt8]) {
        let isNegative = text.first == UInt8(ascii: "-")
        let yearStart = isNegative ? 1 : 0
        var yearEnd = yearStart
        while yearEnd < text.count, text[yearEnd].isASCIIDigit {
            yearEnd += 1
        }
        // Four digits, or more without a leading zero, as the timestamp writes a year; at most 12,
        // already far past the 292 million years a millisecond count in Int64 reaches, so the
        // day count below can't overflow.
        let yearDigits = yearEnd - yearStart
        guard yearDigits >= 4, yearDigits <= 12, yearDigits == 4 || text[yearStart] != UInt8(ascii: "0") else { return nil }
        let rest = text[yearEnd...]
        guard rest.count == 20, let magnitude = Int64(decimal: text[yearStart ..< yearEnd]) else { return nil }
        // Year 0 is written 0000, never -0000.
        guard !isNegative || magnitude > 0 else { return nil }
        let separators: [(offset: Int, byte: Unicode.Scalar)] = [(0, "-"), (3, "-"), (6, "T"), (9, ":"), (12, ":"), (15, "."), (19, "Z")]
        for (offset, byte) in separators where rest[rest.startIndex + offset] != UInt8(ascii: byte) {
            return nil
        }
        func field(_ offset: Int, digits: Int) -> Int64? {
            let start = rest.startIndex + offset
            return Int64(decimal: rest[start ..< start + digits])
        }
        guard let month = field(1, digits: 2), let day = field(4, digits: 2), let hour = field(7, digits: 2),
              let minute = field(10, digits: 2), let second = field(13, digits: 2), let millisecond = field(16, digits: 3)
        else { return nil }
        let date = CivilDate(year: isNegative ? -magnitude : magnitude, month: month, day: day)
        guard (1 ... 12).contains(month), (1 ... date.daysInMonth).contains(day), hour < 24, minute < 60, second < 60 else { return nil }
        let millisecondOfDay = ((hour * 60 + minute) * 60 + second) * 1000 + millisecond
        // Int128: a day count times a day's milliseconds can pass Int64 where the sum, for a time
        // late on a day before 1970, doesn't.
        guard let milliseconds = Int64(exactly: Int128(date.daysSince1970) * 86_400_000 + Int128(millisecondOfDay)) else { return nil }
        self = milliseconds
    }

    /// The number ASCII decimal `digits` spell, or `nil` when one isn't a digit; at most 18 of
    /// them, so it fits.
    fileprivate init?(decimal digits: ArraySlice<UInt8>) {
        var value: Int64 = 0
        for digit in digits {
            guard digit.isASCIIDigit else { return nil }
            value = value * 10 + Int64(digit - UInt8(ascii: "0"))
        }
        self = value
    }
}

extension UInt8 {
    /// Whether the byte is an ASCII digit, `0` to `9`.
    fileprivate var isASCIIDigit: Bool {
        (UInt8(ascii: "0") ... UInt8(ascii: "9")).contains(self)
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
