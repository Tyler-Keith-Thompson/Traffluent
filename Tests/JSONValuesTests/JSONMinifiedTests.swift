import JSONValues
import Testing

@Suite("JSON.minified")
struct JSONMinifiedTests {
    @Test("A value renders with no whitespace between its tokens, keys by their bytes")
    func noWhitespace() {
        let sut = JSON.object(["b": .array([.integer(1), .boolean(false), .null]), "a": .string("x y"), "c": .object(["e": .integer(2), "d": .array([])])])
        let expected = #"{"a":"x y","b":[1,false,null],"c":{"d":[],"e":2}}"#

        let actual = sut.minified

        #expect(actual == expected)
    }

    @Test("An empty array and an empty object render as [] and {}")
    func emptyContainers() {
        let sut = JSON.object(["a": .array([]), "b": .object([:])])
        let expected = #"{"a":[],"b":{}}"#

        let actual = sut.minified

        #expect(actual == expected)
    }

    @Test("A NaN or infinite number renders as null, as JSON.stringify writes it", arguments: [Double.nan, .infinity, -.infinity, .signalingNaN])
    func nonFiniteNumber(value: Double) {
        let sut = JSON.array([.number(value)])
        let expected = "[null]"

        let actual = sut.minified

        #expect(actual == expected)
    }

    @Test("The largest finite numbers render as numbers, not null", arguments: [Double.greatestFiniteMagnitude, -.greatestFiniteMagnitude])
    func largestFiniteNumber(value: Double) {
        let sut = JSON.number(value)
        let expected = value.description

        let actual = sut.minified

        #expect(actual == expected)
    }

    @Test("A NaN or infinite member's value renders as null inside an object")
    func nonFiniteMember() {
        let sut = JSON.object(["a": .number(.nan), "b": .number(0.5)])
        let expected = #"{"a":null,"b":0.5}"#

        let actual = sut.minified

        #expect(actual == expected)
    }
}
