import JSONValues
import Testing

@Suite("JSON.rendered")
struct JSONRenderedTests {
    @Test("A value renders with two-space indentation, keys by their bytes and empty containers on one line")
    func nestedValue() {
        let sut = JSON.object([
            "g": .object(["x": .string("y")]),
            "b": .array([.integer(1), .boolean(false)]),
            "a": .object([:]),
            "c": .array([]),
            "f": .number(0.5),
            "d": .null,
            "e": .boolean(true),
        ])
        let expected = """
            {
              "a": {},
              "b": [
                1,
                false
              ],
              "c": [],
              "d": null,
              "e": true,
              "f": 0.5,
              "g": {
                "x": "y"
              }
            }
            """

        let actual = sut.rendered

        #expect(actual == expected)
    }

    @Test("Nested arrays indent two spaces a level, each element but the last followed by a comma")
    func nestedArrays() {
        let sut = JSON.array([.array([.integer(1), .integer(2)]), .integer(3)])
        let expected = "[\n  [\n    1,\n    2\n  ],\n  3\n]"

        let actual = sut.rendered

        #expect(actual == expected)
    }

    @Test("Nested objects indent two spaces a level, each member but the last followed by a comma")
    func nestedObjects() {
        let sut = JSON.object(["a": .object(["b": .integer(1), "c": .integer(2)]), "d": .integer(3)])
        let expected = "{\n  \"a\": {\n    \"b\": 1,\n    \"c\": 2\n  },\n  \"d\": 3\n}"

        let actual = sut.rendered

        #expect(actual == expected)
    }

    @Test("A string escapes quotes, backslashes and control characters, and keeps other characters as they are")
    func escapes() {
        let sut = JSON.string("\"\\\n\r\t\u{08}\u{0C}\u{01}\u{1F}é😀/")
        let expected = #""\"\\\n\r\t\b\f\u0001\u001Fé😀/""#

        let actual = sut.rendered

        #expect(actual == expected)
    }

    @Test("A NaN or infinite number renders as null")
    func nonFiniteNumber() {
        let sut = JSON.array([.number(.nan), .number(-.infinity)])
        let expected = "[\n  null,\n  null\n]"

        let actual = sut.rendered

        #expect(actual == expected)
    }
}
