import JSONValues
import Testing

@Suite("JSON(parsing:)")
struct JSONParsingTests {
    @Test("Each kind of JSON text reads as its case", arguments: [
        ("null", JSON.null),
        ("true", .boolean(true)),
        ("false", .boolean(false)),
        ("42", .integer(42)),
        ("-9223372036854775808", .integer(-9_223_372_036_854_775_808)),
        ("0.5", .number(0.5)),
        ("2.0", .integer(2)),
        ("1e19", .number(1e19)),
        (#""a\nb""#, .string("a\nb")),
        ("[1, null]", .array([.integer(1), .null])),
        (#"{"a": {"b": []}}"#, .object(["a": .object(["b": .array([])])])),
    ])
    func eachKind(text: String, expected: JSON) {
        let actual = JSON(parsing: Array(text.utf8))

        #expect(actual == expected)
    }

    @Test("Bytes that aren't JSON read as nil", arguments: ["", "{", "nul", #"{"a" 1}"#])
    func notJSON(text: String) {
        let actual = JSON(parsing: Array(text.utf8))

        #expect(actual == nil)
    }
}
