import JSONValues
import Testing

@Suite("JSON.compact")
struct JSONCompactTests {
    @Test("A value renders on one line, a space after each comma and colon, keys by their bytes")
    func oneLine() {
        let sut = JSON.array([.integer(1), .object(["b": .integer(2), "a": .string("x")]), .null])
        let expected = #"[1, {"a": "x", "b": 2}, null]"#

        let actual = sut.compact

        #expect(actual == expected)
    }

    @Test("An empty array and an empty object render as [] and {}")
    func emptyContainers() {
        let sut = JSON.array([.array([]), .object([:])])
        let expected = "[[], {}]"

        let actual = sut.compact

        #expect(actual == expected)
    }
}
