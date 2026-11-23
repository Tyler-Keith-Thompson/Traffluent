import Destinations
import Events
import Foundation
import Testing
import Trackers

@Suite("redactingSensitiveValues()", .timeLimit(.minutes(1)))
struct RedactingSensitiveValuesTests {
    struct SignedUp: Event {
        var plan: String
        var email: Sensitive<String>
        var age: Sensitive<Int>?
    }

    @Test("By default a destination reveals a tracked record's sensitive values")
    func revealedByDefault() async throws {
        let sut = InMemoryDestination()
        let tracker = Tracker()
        let expectedEmail = "ada@example.com"
        let expectedAge = 36

        tracker.track(SignedUp(plan: "pro", email: Sensitive("ada@example.com"), age: Sensitive(36)))
        await tracker.finish()
        try await tracker.records.batch(strategy: .count(1)).deliver(to: sut).execute()

        let record = try #require(sut.records.first)
        let event = try #require(record.event as? SignedUp)
        let age = try #require(event.age)
        #expect(record.reveal(event.email) == expectedEmail)
        #expect(record.reveal(age) == expectedAge)
        #expect(record.revealsSensitiveValues)
    }

    @Test("A redacting destination receives the redacted value, nil, for every sensitive property, and the rest as tracked")
    func redacted() async throws {
        let recorder = InMemoryDestination()
        let tracker = Tracker()
        let sut = recorder.redactingSensitiveValues()
        let expectedPlan = "pro"

        tracker.track(SignedUp(plan: "pro", email: Sensitive("ada@example.com"), age: Sensitive(36)))
        await tracker.finish()
        try await tracker.records.batch(strategy: .count(1)).deliver(to: sut).execute()

        let record = try #require(recorder.records.first)
        let event = try #require(record.event as? SignedUp)
        let age = try #require(event.age)
        #expect(record.reveal(event.email) == nil)
        #expect(record.reveal(age) == nil)
        #expect(!record.revealsSensitiveValues)
        #expect(event.plan == expectedPlan)
        #expect(record.name == "SignedUp")
    }

    @Test("Redacting one destination leaves the other destinations revealing")
    func otherDestinationsReveal() async throws {
        let redacted = InMemoryDestination()
        let revealing = InMemoryDestination()
        let tracker = Tracker()
        let expected = "ada@example.com"

        tracker.track(SignedUp(plan: "pro", email: Sensitive("ada@example.com"), age: nil))
        await tracker.finish()
        try await tracker.records.batch(strategy: .count(1)).deliver(to: redacted.redactingSensitiveValues(), revealing).execute()

        let redactedRecord = try #require(redacted.records.first)
        let revealingRecord = try #require(revealing.records.first)
        let event = try #require(revealingRecord.event as? SignedUp)
        #expect(redactedRecord.reveal(event.email) == nil)
        #expect(revealingRecord.reveal(event.email) == expected)
    }

    @Test("A redacted record stays redacted through a copy that changes its event")
    func copyStaysRedacted() async throws {
        let recorder = InMemoryDestination()
        let tracker = Tracker()

        tracker.track(SignedUp(plan: "pro", email: Sensitive("ada@example.com"), age: nil))
        await tracker.finish()
        try await tracker.records.batch(strategy: .count(1)).deliver(to: recorder.redactingSensitiveValues()).execute()

        var copy = try #require(recorder.records.first)
        copy.event = SignedUp(plan: "free", email: Sensitive("grace@example.com"), age: nil)
        let event = try #require(copy.event as? SignedUp)
        #expect(copy.reveal(event.email) == nil)
    }
}
