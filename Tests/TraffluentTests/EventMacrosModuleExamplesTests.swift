// The example of the EventMacros module's landing article
// (Sources/EventMacros/EventMacros.docc/EventMacros.md), verbatim, so the article cannot drift from
// the code.

import EventMacros
import Testing

// Private: its events share their names with other events of this test target, and @Event
// leaves a private type's events out of the link check of names (DefiningEvents, Limits).
@Suite("EventMacros module examples")
private struct EventMacrosModuleExamplesTests {
    @Event(name: "search_performed", consent: .functional, version: 2)
    struct SearchPerformed {
        @Constrained(.minLength(1), .maxLength(200))
        var query: String
        var resultCount: Int
        var filter: String?
    }

    @Test("@Event and @Constrained")
    func eventMacros() {
        let names = SearchPerformed.schema.properties.map(\.name)  // ["query", "resultCount", "filter"]

        let expectedNames = ["query", "resultCount", "filter"]
        let expectedName = "search_performed"
        let expectedVersion = 2
        #expect(names == expectedNames)
        #expect(SearchPerformed.name == expectedName)
        #expect(SearchPerformed.schemaVersion == expectedVersion)
        #expect(SearchPerformed.consentCategory == .functional)
    }
}
