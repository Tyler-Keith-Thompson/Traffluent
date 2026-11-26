import Events
import Testing

@Suite("Refined")
struct RefinedTests {
    enum PlanName: Refinement {
        static var constraints: [Constraint<String>] {
            get throws(InvalidConstraint) { try [.minLength(1), .maxLength(8)] }
        }
    }

    enum CouponCode: Refinement {
        static var constraints: [Constraint<String>] {
            get throws(InvalidConstraint) { try [.pattern("^[A-Z0-9]{6}$", example: "SPRING")] }
        }
    }

    enum Percent: Refinement {
        static var constraints: [Constraint<Int>] {
            get throws(InvalidConstraint) { try [.minimum(0), .maximum(100)] }
        }
    }

    enum Ratio: Refinement {
        static var constraints: [Constraint<Double>] {
            get throws(InvalidConstraint) { try [.minimum(0), .maximum(1)] }
        }
    }

    enum Tags: Refinement {
        static var constraints: [Constraint<[String]>] {
            get throws(InvalidConstraint) { try [.minItems(1), .maxItems(3)] }
        }
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

        let plain = try Refined<String, PlanName>("pro")
        let checked = try Refined<String, PlanName>("pro")

        #expect(plain.value == expected)
        #expect(checked.value == expected)
    }

    @Test("The initializer throws the keyword of the constraint the value breaks")
    func unsatisfied() {
        #expect(throws: UnsatisfiedConstraint.minLength) { try Refined<String, PlanName>("") }
        #expect(throws: UnsatisfiedConstraint.maxLength) { try Refined<String, PlanName>("enterprise") }
        #expect(throws: UnsatisfiedConstraint.pattern) { try Refined<String, CouponCode>("spring") }
        #expect(throws: UnsatisfiedConstraint.minimum) { try Refined<Int, Percent>(-1) }
        #expect(throws: UnsatisfiedConstraint.maximum) { try Refined<Int, Percent>(101) }
        #expect(throws: UnsatisfiedConstraint.minItems) { try Refined<[String], Tags>([]) }
        #expect(throws: UnsatisfiedConstraint.maxItems) { try Refined<[String], Tags>(["a", "b", "c", "d"]) }
    }

    @Test("The initializer accepts each bound itself")
    func bounds() throws {
        let values = [
            try Refined<String, PlanName>("a").value.count,
            try Refined<String, PlanName>("12345678").value.count,
            try Refined<Int, Percent>(0).value,
            try Refined<Int, Percent>(100).value,
            try Refined<[String], Tags>(["a"]).value.count,
            try Refined<[String], Tags>(["a", "b", "c"]).value.count,
        ]
        let expected = [1, 8, 0, 100, 1, 3]

        #expect(values == expected)
        #expect(try Refined<Double, Ratio>(1).value == 1)
    }

    @Test("The initializer throws the first constraint broken, in the rule's order")
    func firstBroken() {
        enum Both: Refinement {
            static var constraints: [Constraint<String>] {
                get throws(InvalidConstraint) { try [.maxLength(1), .pattern("^[0-9]+$", example: "1")] }
            }
        }

        #expect(throws: UnsatisfiedConstraint.maxLength) { try Refined<String, Both>("ab") }
        #expect(throws: UnsatisfiedConstraint.pattern) { try Refined<String, Both>("a") }
    }

    @Test("A rule with no constraints accepts every value")
    func noConstraints() throws {
        let expected = ""

        let actual = try Refined<String, Unconstrained>("").value

        #expect(actual == expected)
    }

    @Test("Refined values compare, hash and describe as their values do", .tags(.conformance))
    func conformances() throws {
        let small = try Refined<Int, Percent>(3)
        let large = try Refined<Int, Percent>(40)
        let expectedDescription = "40"

        #expect(try small == Refined<Int, Percent>(3))
        #expect(try small.hashValue == Refined<Int, Percent>(3).hashValue)
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
