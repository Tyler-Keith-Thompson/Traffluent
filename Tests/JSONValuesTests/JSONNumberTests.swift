import JSONValues
import Testing

@Suite("JSON.number(exactly:)")
struct JSONNumberTests {
    @Test("A whole number in Int64's range is an integer, at both ends of the range", arguments: [
        (3.0, Int64(3)),
        (-0.0, Int64(0)),
        (-9_223_372_036_854_775_808.0, Int64.min),
        // The largest Double below 2^63.
        (9_223_372_036_854_774_784.0, Int64(9_223_372_036_854_774_784)),
    ])
    func wholeNumber(value: Double, integer: Int64) {
        let expected = JSON.integer(integer)

        let actual = JSON.number(exactly: value)

        #expect(actual == expected)
    }

    @Test("A fraction, or a whole number past Int64's range, is a number", arguments: [
        0.5,
        -1.25,
        9_223_372_036_854_775_808.0,
        -9_223_372_036_854_777_856.0,
        Double.greatestFiniteMagnitude,
    ])
    func number(value: Double) {
        let expected = JSON.number(value)

        let actual = JSON.number(exactly: value)

        #expect(actual == expected)
    }

    @Test("A NaN or infinite value is no JSON number", arguments: [Double.nan, .infinity, -.infinity])
    func nonFinite(value: Double) {
        let actual = JSON.number(exactly: value)

        #expect(actual == nil)
    }
}
