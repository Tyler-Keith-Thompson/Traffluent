// What @Constrained declares, compiled by the real compiler and run: the schema's keywords, the
// generated constraintViolation(), and a tracker rejecting each kind of violation on its worker.

import Destinations
import EventMacros
import Foundation
import Testing
import Trackers

// Private: its events share their names with other events of this test target, and @Event
// leaves a private type's events out of the link check of names (DefiningEvents, Limits).
@Suite("@Constrained", .timeLimit(.minutes(1)))
private struct EventMacroConstraintTests {
    enum PlanName: Refinement {
        static var constraints: [Constraint<String>] {
            get throws(InvalidConstraint) { try [.minLength(1), .maxLength(16)] }
        }
    }

    @Event(name: "search_performed")
    struct SearchPerformed: Equatable {
        @Constrained(.minLength(1), .maxLength(8))
        var query: String
        @Constrained(.pattern("^[a-z]{2}-[A-Z]{2}$", example: "en-GB"))
        var locale: String?
        @Constrained(.minimum(0), .maximum(100))
        var resultCount: Int
        @Constrained(.minimum(0.5), .maximum(2.5))
        var ratio: Double
        @Constrained(.minItems(1), .maxItems(2))
        var filters: [String]
        var page: Int
    }

    @Event
    struct SignedUp {
        var plan: Refined<String, PlanName>
        var email: Sensitive<Refined<String, PlanName>>?
        var referrer: String?
    }

    @Event
    struct Unconstrained {
        var screen: String
    }

    enum Tenth: Refinement {
        static var constraints: [Constraint<Float>] {
            get throws(InvalidConstraint) { try [.maximum(0.1)] }
        }
    }

    @Event
    struct Measured {
        @Constrained(.maximum(0.1))
        var declared: Float
        var refined: Refined<Float, Tenth>
        @Constrained(.maximum(9_007_199_254_740_992))
        var largest: Int
    }

    static let valid = SearchPerformed(query: "shoes", locale: "en-GB", resultCount: 10, ratio: 1, filters: ["red"], page: 1)

    @Test("The schema lists each property's declared keywords, in order, and none for the rest")
    func declaredKeywords() {
        let expected: [[ValidationKeyword]] = [
            [.minLength(1), .maxLength(8)],
            [.pattern("^[a-z]{2}-[A-Z]{2}$", example: "en-GB")],
            [.minimum(0), .maximum(100)],
            [.minimum(0.5), .maximum(2.5)],
            [.minItems(1), .maxItems(2)],
            [],
        ]

        let actual = SearchPerformed.schema.properties.map(\.keywords)

        #expect(actual == expected)
    }

    @Test("A Float bound reaches the schema as 0.1 whether @Constrained declares it or a Refined type's rule does, and 2^53 is an integer's largest bound")
    func floatKeywordsAgree() throws {
        let expected: [[ValidationKeyword]] = [[.maximum(0.1)], [.maximum(0.1)], [.maximum(9_007_199_254_740_992)]]
        let event = Measured(declared: 0.1, refined: try Refined(0.1), largest: 9_007_199_254_740_992)

        let actual = Measured.schema.properties.map(\.keywords)

        #expect(actual == expected)
        #expect(event.constraintViolation() == nil)
    }

    @Test("The schema lists a refined property's rule, through Optional and Sensitive too")
    func refinedKeywords() {
        let expected: [[ValidationKeyword]] = [[.minLength(1), .maxLength(16)], [.minLength(1), .maxLength(16)], []]

        let actual = SignedUp.schema.properties.map(\.keywords)

        #expect(actual == expected)
    }

    @Test("A valid event has no violation, and an event without constraints never has one")
    func valid() {
        let unconstrained = Unconstrained(screen: "")

        #expect(Self.valid.constraintViolation() == nil)
        #expect(unconstrained.constraintViolation() == nil)
    }

    @Test("An optional property's constraints apply only when it holds a value")
    func optionalAbsent() {
        var sut = Self.valid
        sut.locale = nil

        let actual = sut.constraintViolation()

        #expect(actual == nil)
    }

    @Test("The first violation, in declaration order, names the property and the keyword it breaks")
    func firstViolation() {
        var sut = Self.valid
        sut.query = ""
        sut.resultCount = -1
        let expected = ConstraintViolation(property: "query", keyword: .minLength(1))

        let actual = sut.constraintViolation()

        #expect(actual == expected)
    }

    /// One edit of the valid event per keyword, each breaking that keyword alone.
    static let violations: [(edit: @Sendable (inout SearchPerformed) -> Void, expected: ConstraintViolation)] = [
        ({ $0.query = "" }, ConstraintViolation(property: "query", keyword: .minLength(1))),
        ({ $0.query = "sneakers!" }, ConstraintViolation(property: "query", keyword: .maxLength(8))),
        ({ $0.locale = "english" }, ConstraintViolation(property: "locale", keyword: .pattern("^[a-z]{2}-[A-Z]{2}$", example: "en-GB"))),
        ({ $0.resultCount = -1 }, ConstraintViolation(property: "resultCount", keyword: .minimum(0))),
        ({ $0.resultCount = 101 }, ConstraintViolation(property: "resultCount", keyword: .maximum(100))),
        ({ $0.ratio = 0.25 }, ConstraintViolation(property: "ratio", keyword: .minimum(0.5))),
        ({ $0.ratio = 3 }, ConstraintViolation(property: "ratio", keyword: .maximum(2.5))),
        ({ $0.filters = [] }, ConstraintViolation(property: "filters", keyword: .minItems(1))),
        ({ $0.filters = ["a", "b", "c"] }, ConstraintViolation(property: "filters", keyword: .maxItems(2))),
    ]

    @Test("A tracker rejects an event breaking each kind of keyword: it reaches no destination, and the report names the event, the property and the keyword", arguments: 0 ..< 9)
    func rejected(index: Int) async throws {
        var violating = Self.valid
        Self.violations[index].edit(&violating)
        let sut = Tracker(now: { Date(timeIntervalSince1970: 7) })
        let recorder = InMemoryDestination()
        let expectedReport = RejectionReport(
            eventName: "search_performed",
            violation: Self.violations[index].expected,
            recordCount: 1,
            timestamps: Date(timeIntervalSince1970: 7) ... Date(timeIntervalSince1970: 7)
        )
        let expected = [Self.valid]

        sut.track(violating)
        sut.track(Self.valid)
        await sut.finish()
        try await sut.records.batch(strategy: .count(10)).deliver(to: recorder).execute()

        #expect(recorder.events(of: SearchPerformed.self) == expected)
        var reports = sut.rejectionReports.makeAsyncIterator()
        #expect(await reports.next() == expectedReport)
        #expect(await reports.next() == nil)
    }

    @Test("Each bound accepts the value at the bound itself")
    func bounds() {
        let atBounds = [
            SearchPerformed(query: "a", locale: "en-GB", resultCount: 0, ratio: 0.5, filters: ["a"], page: 0),
            SearchPerformed(query: "12345678", locale: "fr-FR", resultCount: 100, ratio: 2.5, filters: ["a", "b"], page: 0),
        ]

        let actual = atBounds.map { $0.constraintViolation() }

        #expect(actual == [nil, nil])
    }
}
