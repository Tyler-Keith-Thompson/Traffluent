import Destinations
import Events
import Foundation
import InMemoryLogging
import Instrumentation
import Logging
import LoggingDestinations
import Testing
import Trackers

@Suite("LoggerDestination", .timeLimit(.minutes(1)))
struct LoggerDestinationTests {
    struct SignedUp: Event {
        var plan: String
    }

    enum SessionKey: ServiceContextKey {
        typealias Value = String
        static let nameOverride: String? = "session"
    }

    @Test("Each event is written at info, named after the event, with its description, time and call site as metadata")
    func writes() async throws {
        let handler = InMemoryLogHandler()
        let sut = LoggerDestination(logger: Logger(label: "test") { _ in handler })
        let tracker = Tracker(now: { Date(timeIntervalSince1970: 1_700_000_000) })
        let expectedMetadata: Logger.Metadata = [
            "event": "SignedUp(plan: \"pro\")",
            "event.timestamp": "2023-11-14T22:13:20Z",
            "code.filepath": "M/A.swift",
            "code.function": "f()",
            "code.lineno": "4",
            "code.column": "2",
        ]

        tracker.track(SignedUp(plan: "pro"), file: "/x/A.swift", fileID: "M/A.swift", function: "f()", line: 4, column: 2)
        await tracker.finish()
        try await tracker.records.batch().deliver(to: sut).execute()

        let entry = try #require(handler.entries.first)
        #expect(handler.entries.count == 1)
        #expect(entry.level == .info)
        #expect(entry.message.description == "SignedUp")
        #expect(entry.metadata == expectedMetadata)
    }

    // The handler's entries don't hold the line Logger was given, only the metadata, so this pins
    // that the record is written rather than which line it carries.
    @Test("A record whose call site has a negative line is still written, its code.lineno as given", arguments: [-1, Int.min])
    func negativeLine(line: Int) async throws {
        let handler = InMemoryLogHandler()
        let sut = LoggerDestination(logger: Logger(label: "test") { _ in handler })
        let tracker = Tracker(now: { Date(timeIntervalSince1970: 1_700_000_000) })
        let expected: Logger.MetadataValue = "\(line)"

        tracker.track(SignedUp(plan: "pro"), file: "/x/A.swift", fileID: "M/A.swift", function: "f()", line: line, column: 2)
        await tracker.finish()
        try await tracker.records.batch().deliver(to: sut).execute()

        let entry = try #require(handler.entries.first)
        #expect(handler.entries.count == 1)
        #expect(entry.metadata["code.lineno"] == expected)
    }

    @Test("A record whose call site was dropped is written without code metadata")
    func droppedCallSite() async throws {
        let handler = InMemoryLogHandler()
        let sut = LoggerDestination(logger: Logger(label: "test") { _ in handler }).droppingCallSite()
        let tracker = Tracker(now: { Date(timeIntervalSince1970: 1_700_000_000) })
        let expectedMetadata: Logger.Metadata = [
            "event": "SignedUp(plan: \"pro\")",
            "event.timestamp": "2023-11-14T22:13:20Z",
        ]

        tracker.track(SignedUp(plan: "pro"), file: "/x/A.swift", fileID: "M/A.swift", function: "f()", line: 4, column: 2)
        await tracker.finish()
        try await tracker.records.batch().deliver(to: sut).execute()

        let entry = try #require(handler.entries.first)
        #expect(entry.message.description == "SignedUp")
        #expect(entry.metadata == expectedMetadata)
    }

    @Test("A sensitive property is written as <redacted>, never its value")
    func sensitive() async throws {
        struct SignedIn: Event {
            var email: Sensitive<String>
        }
        let handler = InMemoryLogHandler()
        let sut = LoggerDestination(logger: Logger(label: "test") { _ in handler })
        let tracker = Tracker()
        let expected: Logger.MetadataValue = "SignedIn(email: Sensitive(<redacted>))"

        tracker.track(SignedIn(email: Sensitive("ada@example.com")))
        await tracker.finish()
        try await tracker.records.batch().deliver(to: sut).execute()

        let actual = try #require(handler.entries.first).metadata["event"]
        #expect(actual == expected)
    }

    @Test("Values of the record's ServiceContext are written as metadata under their key names")
    func context() async throws {
        let handler = InMemoryLogHandler()
        let sut = LoggerDestination(logger: Logger(label: "test") { _ in handler })
        let tracker = Tracker()
        var context = ServiceContext.topLevel
        context[SessionKey.self] = "s-1"
        let expected: Logger.MetadataValue = "s-1"

        ServiceContext.withValue(context) {
            tracker.track(SignedUp(plan: "pro"))
        }
        await tracker.finish()
        try await tracker.records.batch().deliver(to: sut).execute()

        let actual = try #require(handler.entries.first).metadata["session"]
        #expect(actual == expected)
    }

    @Test("The level is configurable")
    func level() async throws {
        var handler = InMemoryLogHandler()
        handler.logLevel = .trace
        let sut = LoggerDestination(logger: Logger(label: "test") { _ in handler }, level: .debug)
        let tracker = Tracker()
        let expected = Logger.Level.debug

        tracker.track(SignedUp(plan: "pro"))
        await tracker.finish()
        try await tracker.records.batch().deliver(to: sut).execute()

        let actual = try #require(handler.entries.first).level
        #expect(actual == expected)
    }

    @Test("A batch is written in order, one entry per record")
    func order() async throws {
        let handler = InMemoryLogHandler()
        let sut = LoggerDestination(logger: Logger(label: "test") { _ in handler })
        let tracker = Tracker()
        let expected = ["SignedUp(plan: \"a\")", "SignedUp(plan: \"b\")", "SignedUp(plan: \"c\")"]

        for plan in ["a", "b", "c"] {
            tracker.track(SignedUp(plan: plan))
        }
        await tracker.finish()
        try await tracker.records.batch().deliver(to: sut).execute()

        let actual = handler.entries.map { $0.metadata["event"]?.description }
        #expect(actual == expected)
    }

    @Test("A context value named like a fixed key doesn't replace the event or its call site")
    func fixedKeysWin() async throws {
        enum Clash: ServiceContextKey {
            typealias Value = String
            static let nameOverride: String? = "event"
        }
        let handler = InMemoryLogHandler()
        let sut = LoggerDestination(logger: Logger(label: "test") { _ in handler })
        let tracker = Tracker()
        var context = ServiceContext.topLevel
        context[Clash.self] = "clash"
        let expected: Logger.MetadataValue = "SignedUp(plan: \"pro\")"

        ServiceContext.withValue(context) {
            tracker.track(SignedUp(plan: "pro"))
        }
        await tracker.finish()
        try await tracker.records.batch().deliver(to: sut).execute()

        let actual = try #require(handler.entries.first).metadata["event"]
        #expect(actual == expected)
    }
}
