// Property tests against Foundation's JSONDecoder as the reference reader: whatever a value holds,
// its minified and rendered text read back as the same value.

import JSONValues
import PropertyBased
import Testing
import TraffluentTestSupport

@Suite("JSON: properties")
struct JSONPropertyTests {
    @Test("Any value's minified and rendered text read back as the value", .tags(.randomized))
    func roundTrip() async {
        // The characters a string must escape, or keep as they are in one to four UTF-8 bytes.
        let characters: [Character] = ["a", "Z", "0", " ", "\"", "\\", "/", "\n", "\r", "\t", "\u{08}", "\u{0C}", "\u{00}", "\u{01}", "\u{1F}", "\u{7F}", "é", "€", "😀"]
        let strings = Gen<Character?>.element(of: characters).map { $0! }.string(of: 0...8).array(of: 0...6)

        await propertyCheck(count: 300, input: strings, Gen.int64(), Gen.double(in: -1e9...1e9)) { texts, integer, number in
            let elements: [JSON] = texts.map(JSON.string) + [.integer(integer), JSON.number(exactly: number) ?? .null, .boolean(integer.isMultiple(of: 2)), .null]
            let members = Dictionary(texts.enumerated().map { ("\($0.offset)" + $0.element, JSON.array([.string($0.element)])) }) { first, _ in first }
            let expected = JSON.object(members.merging(["elements": .array(elements), "empty": .object([:])]) { first, _ in first })

            let minified = JSON(parsing: Array(expected.minified.utf8))
            let rendered = JSON(parsing: Array(expected.rendered.utf8))

            #expect(minified == expected)
            #expect(rendered == expected)
        }
    }
}
