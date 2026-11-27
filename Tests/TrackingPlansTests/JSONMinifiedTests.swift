import Testing
import TrackingPlans

@Suite("JSON.minified")
struct JSONMinifiedTests {
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
