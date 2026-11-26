import Events
import Testing

@Suite("Constraint: arguments")
struct ConstraintArgumentTests {
    enum Broken: Refinement {
        static var constraints: [Constraint<String>] {
            get throws(InvalidConstraint) { try [.minLength(1), .maxLength(-1)] }
        }
    }

    @Test("A negative length or count throws negativeCount", arguments: [-1, Int.min])
    func negativeCount(_ count: Int) {
        #expect(throws: InvalidConstraint.negativeCount) { try Constraint<String>.minLength(count) }
        #expect(throws: InvalidConstraint.negativeCount) { try Constraint<String>.maxLength(count) }
        #expect(throws: InvalidConstraint.negativeCount) { try Constraint<[Int]>.minItems(count) }
        #expect(throws: InvalidConstraint.negativeCount) { try Constraint<[Int]>.maxItems(count) }
    }

    @Test("A length or count of 0 is accepted")
    func zeroCount() throws {
        let expected: [ValidationKeyword] = [.minLength(0), .maxLength(0), .minItems(0), .maxItems(0)]

        let actual = [
            try Constraint<String>.minLength(0).keyword,
            try Constraint<String>.maxLength(0).keyword,
            try Constraint<[Int]>.minItems(0).keyword,
            try Constraint<[Int]>.maxItems(0).keyword,
        ]

        #expect(actual == expected)
    }

    @Test("A floating-point bound that is NaN or infinite throws nonFiniteBound", arguments: [Double.nan, .infinity, -.infinity])
    func nonFiniteBound(_ bound: Double) {
        #expect(throws: InvalidConstraint.nonFiniteBound) { try Constraint<Double>.minimum(bound) }
        #expect(throws: InvalidConstraint.nonFiniteBound) { try Constraint<Double>.maximum(bound) }
        #expect(throws: InvalidConstraint.nonFiniteBound) { try Constraint<Float>.minimum(Float(bound)) }
        #expect(throws: InvalidConstraint.nonFiniteBound) { try Constraint<Float>.maximum(Float(bound)) }
    }

    @Test("The largest finite bounds are accepted")
    func largestFiniteBounds() throws {
        let expected: [ValidationKeyword] = [.minimum(-.greatestFiniteMagnitude), .maximum(.greatestFiniteMagnitude)]

        let actual = [
            try Constraint<Double>.minimum(-.greatestFiniteMagnitude).keyword,
            try Constraint<Double>.maximum(.greatestFiniteMagnitude).keyword,
        ]

        #expect(actual == expected)
    }

    @Test("A pattern that isn't a regular expression throws invalidPattern")
    func invalidPattern() {
        #expect(throws: InvalidConstraint.invalidPattern) { try Constraint<String>.pattern("(", example: "(") }
    }

    @Test("A pattern that doesn't match its example throws exampleMismatch")
    func exampleMismatch() {
        #expect(throws: InvalidConstraint.exampleMismatch) { try Constraint<String>.pattern("^[0-9]+$", example: "abc") }
    }

    @Test("A rule whose constraints throw refines no value: the initializer throws invalidConstraint, and its type promises no keyword")
    func brokenRule() {
        let expectedKeywords: [ValidationKeyword] = []

        #expect(throws: UnsatisfiedConstraint.invalidConstraint) { try Refined<String, Broken>("a") }
        #expect(ValidationKeyword.keywords(of: Refined<String, Broken>.self) == expectedKeywords)
    }

    struct Holder {
        var broken: Refined<String, Broken>
        var optional: Refined<String, Broken>?
        var sensitive: Sensitive<Refined<String, Broken>>
        var valid: Refined<String, Valid>?
        var plain: String
    }

    enum Valid: Refinement {
        static var constraints: [Constraint<String>] {
            get throws(InvalidConstraint) { try [.minLength(1)] }
        }
    }

    @Test("A property says its type's rule throws, through Optional and Sensitive too, and a valid rule or a plain type doesn't")
    func brokenRuleFlagged() {
        let expected = [true, true, true, false, false]

        let actual = [
            ValidationKeyword.hasInvalidConstraint(of: \Holder.broken),
            ValidationKeyword.hasInvalidConstraint(of: \Holder.optional),
            ValidationKeyword.hasInvalidConstraint(of: \Holder.sensitive),
            ValidationKeyword.hasInvalidConstraint(of: \Holder.valid),
            ValidationKeyword.hasInvalidConstraint(of: \Holder.plain),
        ]

        #expect(actual == expected)
    }
}
