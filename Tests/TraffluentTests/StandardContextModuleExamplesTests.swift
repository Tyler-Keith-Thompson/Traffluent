// The example of the StandardContext module's landing article
// (Sources/StandardContext/StandardContext.docc/StandardContext.md), verbatim, so the article
// cannot drift from the code.

import Testing
import Traffluent

@Suite("StandardContext module examples", .timeLimit(.minutes(1)))
struct StandardContextModuleExamplesTests {
    struct SignedUp: Event {
        var plan: String
    }

    @Test("Standard context: each value under its key")
    func standardContext() async throws {
        let tracker = Tracker(enrichers: [.application(), .operatingSystem(), .locale(), .network()])
        tracker.track(SignedUp(plan: "pro"))
        // A destination reads each value from the record's context:
        // record.context[ApplicationKey.self]?.version, record.context[OperatingSystemKey.self]?.name
        await tracker.finish()

        var records = tracker.records.makeAsyncIterator()
        let record = try #require(await records.next())
        let expectedApplication: ApplicationKey.Value = .current
        let expectedSystem: OperatingSystemKey.Value = .current
        #expect(record.context[ApplicationKey.self] == expectedApplication)
        #expect(record.context[OperatingSystemKey.self] == expectedSystem)
        #expect(record.context[LocaleKey.self] != nil)
    }
}
