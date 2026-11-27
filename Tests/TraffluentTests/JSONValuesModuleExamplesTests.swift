// The example of the JSONValues module's landing article
// (Sources/JSONValues/JSONValues.docc/JSONValues.md), verbatim, so the article cannot drift from
// the code.

import JSONValues
import Testing

@Suite("JSONValues module examples", .timeLimit(.minutes(1)))
struct JSONValuesModuleExamplesTests {
    @Test("A request body renders minified, its keys in the order of their bytes")
    func minifiedBody() {
        let body: JSON = .object([
            "event": .string("signed_up"),
            "at": JSON.number(exactly: 1_500) ?? .null,
            "ratio": JSON.number(exactly: 0.25) ?? .null,
            "tags": .array([.string("pro"), .boolean(true)]),
        ])
        let text = body.minified  // {"at":1500,"event":"signed_up","ratio":0.25,"tags":["pro",true]}

        let expected = #"{"at":1500,"event":"signed_up","ratio":0.25,"tags":["pro",true]}"#
        #expect(text == expected)
    }
}
