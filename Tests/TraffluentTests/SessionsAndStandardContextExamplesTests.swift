// The examples of the "Sessions and Standard Context" article
// (Sources/Traffluent/Traffluent.docc/SessionsAndStandardContext.md), verbatim, so the article
// cannot drift from the code.

import Foundation
import Testing
import Traffluent

@Suite("Sessions and standard context examples", .timeLimit(.minutes(1)))
struct SessionsAndStandardContextExamplesTests {
    @Event
    struct SignedUp {
        var plan: String
    }

    @Test("Sessions")
    func sessions() async throws {
        let tracker = Tracker(enrichers: [.sessions()])
        tracker.track(SignedUp(plan: "pro"))  // its record's context[SessionKey.self] is the session's UUID
        await tracker.finish()

        var records = tracker.records.makeAsyncIterator()
        let started = try #require(await records.next())
        let signedUp = try #require(await records.next())
        #expect(started.event is SessionStarted)
        #expect(signedUp.context[SessionKey.self] != nil)
        #expect(signedUp.context[SessionKey.self] == started.context[SessionKey.self])
    }

    @Test("Standard context")
    func standardContext() async throws {
        let tracker = Tracker(enrichers: [.application(), .device(), .operatingSystem(), .locale(), .network()])
        tracker.track(SignedUp(plan: "pro"))  // its record's context[OperatingSystemKey.self]?.name is "iOS" on an iPhone
        await tracker.finish()

        var records = tracker.records.makeAsyncIterator()
        let record = try #require(await records.next())
        #expect(record.context[ApplicationKey.self] == ApplicationKey.Value.current)
        #expect(record.context[OperatingSystemKey.self] == OperatingSystemKey.Value.current)
        #expect(record.context[DeviceKey.self] == DeviceKey.Value.current)
        #expect(record.context[LocaleKey.self]?.identifier == Locale.current.identifier)
    }

    @Test("Standard context on a server")
    func standardContextOnAServer() async throws {
        let tracker = Tracker(enrichers: [
            .application(ApplicationKey.Value(bundleIdentifier: "com.example.server", version: "1.2.0", build: "42")),
            .operatingSystem(),
        ])
        tracker.track(SignedUp(plan: "pro"))
        await tracker.finish()

        var records = tracker.records.makeAsyncIterator()
        let record = try #require(await records.next())
        #expect(record.context[ApplicationKey.self]?.version == "1.2.0")
        #expect(record.context[DeviceKey.self] == nil)
    }
}
