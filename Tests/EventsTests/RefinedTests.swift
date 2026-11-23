import Events
import Testing

@Suite("Refined")
struct RefinedTests {
    enum PlanName: Refinement {
        static let constraints: [Constraint<String>] = [.minLength(1), .maxLength(8)]
    }

    enum CouponCode: Refinement {
        static let constraints: [Constraint<String>] = [.pattern("^[A-Z0-9]{6}$", example: "SPRING")]
    }

    enum Percent: Refinement {
        static let constraints: [Constraint<Int>] = [.minimum(0), .maximum(100)]
    }

    enum Ratio: Refinement {
        static let constraints: [Constraint<Double>] = [.minimum(0), .maximum(1)]
    }

    enum Tags: Refinement {
        static let constraints: [Constraint<[String]>] = [.minItems(1), .maxItems(3)]
    }

    enum Unconstrained: Refinement {
        static let constraints: [Constraint<String>] = []
    }

    struct SignedUp: Event {
        var plan: Refined<String, PlanName>
    }

    @Test("A value that satisfies every constraint is kept as it is, by both spellings")
    func satisfied() throws {
        let expected = "pro"

        let plain = Refined<String, PlanName>("pro")
        let checked = try Refined<String, PlanName>(checked: "pro")

        #expect(plain.value == expected)
        #expect(checked.value == expected)
    }

    @Test("The checked spelling throws the keyword of the constraint the value breaks")
    func checkedThrows() {
        #expect(throws: UnsatisfiedConstraint.minLength) { try Refined<String, PlanName>(checked: "") }
        #expect(throws: UnsatisfiedConstraint.maxLength) { try Refined<String, PlanName>(checked: "enterprise") }
        #expect(throws: UnsatisfiedConstraint.pattern) { try Refined<String, CouponCode>(checked: "spring") }
        #expect(throws: UnsatisfiedConstraint.minimum) { try Refined<Int, Percent>(checked: -1) }
        #expect(throws: UnsatisfiedConstraint.maximum) { try Refined<Int, Percent>(checked: 101) }
        #expect(throws: UnsatisfiedConstraint.minItems) { try Refined<[String], Tags>(checked: []) }
        #expect(throws: UnsatisfiedConstraint.maxItems) { try Refined<[String], Tags>(checked: ["a", "b", "c", "d"]) }
    }

    @Test("The checked spelling accepts each bound itself")
    func checkedBounds() throws {
        let values = [
            try Refined<String, PlanName>(checked: "a").value.count,
            try Refined<String, PlanName>(checked: "12345678").value.count,
            try Refined<Int, Percent>(checked: 0).value,
            try Refined<Int, Percent>(checked: 100).value,
            try Refined<[String], Tags>(checked: ["a"]).value.count,
            try Refined<[String], Tags>(checked: ["a", "b", "c"]).value.count,
        ]
        let expected = [1, 8, 0, 100, 1, 3]

        #expect(values == expected)
        #expect(try Refined<Double, Ratio>(checked: 1).value == 1)
    }

    @Test("The checked spelling throws the first constraint broken, in the rule's order")
    func firstBroken() {
        enum Both: Refinement {
            static let constraints: [Constraint<String>] = [.maxLength(1), .pattern("^[0-9]+$", example: "1")]
        }

        #expect(throws: UnsatisfiedConstraint.maxLength) { try Refined<String, Both>(checked: "ab") }
        #expect(throws: UnsatisfiedConstraint.pattern) { try Refined<String, Both>(checked: "a") }
    }

    @Test("A rule with no constraints accepts every value")
    func noConstraints() throws {
        let expected = ""

        let actual = try Refined<String, Unconstrained>(checked: "").value

        #expect(actual == expected)
    }

    @Test("Refined values compare, hash and describe as their values do", .tags(.conformance))
    func conformances() {
        let small = Refined<Int, Percent>(3)
        let large = Refined<Int, Percent>(40)
        let expectedDescription = "40"

        #expect(small == Refined<Int, Percent>(3))
        #expect(small.hashValue == Refined<Int, Percent>(3).hashValue)
        #expect(small < large)
        #expect(small != large)
        #expect(large.description == expectedDescription)
    }

    @Test("A refined type's keywords are its rule's, through Optional and Sensitive too")
    func keywordsOfType() {
        let expected: [ValidationKeyword] = [.minLength(1), .maxLength(8)]

        #expect(ValidationKeyword.keywords(of: Refined<String, PlanName>.self) == expected)
        #expect(ValidationKeyword.keywords(of: Refined<String, PlanName>?.self) == expected)
        #expect(ValidationKeyword.keywords(of: Sensitive<Refined<String, PlanName>>.self) == expected)
        #expect(ValidationKeyword.keywords(of: Sensitive<Refined<String, PlanName>>?.self) == expected)
    }

    @Test("Any other type has no keywords")
    func keywordsOfOtherTypes() {
        let expected: [ValidationKeyword] = []

        #expect(ValidationKeyword.keywords(of: String.self) == expected)
        #expect(ValidationKeyword.keywords(of: String?.self) == expected)
        #expect(ValidationKeyword.keywords(of: Sensitive<String>.self) == expected)
        #expect(ValidationKeyword.keywords(of: [Refined<String, PlanName>].self) == expected)
    }

    @Test("A key path's keywords are its value type's")
    func keywordsOfKeyPath() {
        let expected: [ValidationKeyword] = [.minLength(1), .maxLength(8)]

        let actual = ValidationKeyword.keywords(of: \SignedUp.plan)

        #expect(actual == expected)
    }
}
