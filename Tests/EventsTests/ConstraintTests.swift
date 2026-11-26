import Events
import Testing

@Suite("Constraint")
struct ConstraintTests {
    @Test("minLength accepts a string of exactly its length and counts Unicode scalars, not characters")
    func minLength() throws {
        let sut = try Constraint<String>.minLength(2)
        let combined = "e\u{301}"

        #expect(!sut.isSatisfied(by: ""))
        #expect(!sut.isSatisfied(by: "a"))
        #expect(sut.isSatisfied(by: "ab"))
        #expect(sut.isSatisfied(by: "abc"))
        #expect(sut.isSatisfied(by: combined))
    }

    @Test("minLength 0 accepts the empty string")
    func minLengthZero() throws {
        let sut = try Constraint<String>.minLength(0)

        #expect(sut.isSatisfied(by: ""))
    }

    @Test("maxLength accepts a string of exactly its length and rejects one scalar more")
    func maxLength() throws {
        let sut = try Constraint<String>.maxLength(2)
        let combined = "e\u{301}"
        let flag = "🇬🇧"

        #expect(sut.isSatisfied(by: ""))
        #expect(sut.isSatisfied(by: "ab"))
        #expect(!sut.isSatisfied(by: "abc"))
        #expect(sut.isSatisfied(by: combined))
        #expect(sut.isSatisfied(by: flag))
        #expect(try !Constraint<String>.maxLength(1).isSatisfied(by: combined))
        #expect(try !Constraint<String>.maxLength(0).isSatisfied(by: "a"))
    }

    @Test("A pattern matches anywhere in the string unless it is anchored")
    func pattern() throws {
        let unanchored = try Constraint<String>.pattern("[0-9]+", example: "7")
        let anchored = try Constraint<String>.pattern("^[A-Z]{3}$", example: "ABC")

        #expect(unanchored.isSatisfied(by: "abc123def"))
        #expect(!unanchored.isSatisfied(by: "abc"))
        #expect(anchored.isSatisfied(by: "XYZ"))
        #expect(!anchored.isSatisfied(by: "XYZW"))
        #expect(!anchored.isSatisfied(by: "xyz"))
        #expect(!anchored.isSatisfied(by: ""))
    }

    @Test("An integer's minimum and maximum include the bound itself")
    func integerBounds() throws {
        let minimum = try Constraint<Int>.minimum(-2)
        let maximum = try Constraint<UInt8>.maximum(10)

        #expect(!minimum.isSatisfied(by: -3))
        #expect(minimum.isSatisfied(by: -2))
        #expect(minimum.isSatisfied(by: .max))
        #expect(maximum.isSatisfied(by: 0))
        #expect(maximum.isSatisfied(by: 10))
        #expect(!maximum.isSatisfied(by: 11))
    }

    @Test("An integer bound up to 2^53 is kept exactly, and one past what a Double holds exactly throws inexactBound")
    func integerBoundExact() throws {
        let largestExact = Int64(9_007_199_254_740_992)
        let inexact = Int64(9_007_199_254_740_993)
        let expectedKeyword = ValidationKeyword.minimum(9_007_199_254_740_992)
        let sut = try Constraint<Int64>.minimum(largestExact)

        #expect(sut.keyword == expectedKeyword)
        #expect(!sut.isSatisfied(by: largestExact - 1))
        #expect(sut.isSatisfied(by: largestExact))
        #expect(throws: InvalidConstraint.inexactBound) { try Constraint<Int64>.minimum(inexact) }
        #expect(throws: InvalidConstraint.inexactBound) { try Constraint<Int64>.maximum(inexact) }
        #expect(throws: InvalidConstraint.inexactBound) { try Constraint<UInt64>.maximum(.max) }
    }

    @Test("A floating-point bound includes itself, and NaN satisfies no bound")
    func floatingPointBounds() throws {
        let minimum = try Constraint<Double>.minimum(0.5)
        let maximum = try Constraint<Float>.maximum(1)

        #expect(!minimum.isSatisfied(by: 0.49))
        #expect(minimum.isSatisfied(by: 0.5))
        #expect(!minimum.isSatisfied(by: .nan))
        #expect(maximum.isSatisfied(by: 1))
        #expect(!maximum.isSatisfied(by: 1.01))
        #expect(!maximum.isSatisfied(by: .nan))
    }

    @Test("minItems and maxItems count an array's elements, the bound included")
    func counts() throws {
        let minimum = try Constraint<[String]>.minItems(1)
        let maximum = try Constraint<[Int?]>.maxItems(2)

        #expect(!minimum.isSatisfied(by: []))
        #expect(minimum.isSatisfied(by: ["a"]))
        #expect(maximum.isSatisfied(by: [nil, nil]))
        #expect(!maximum.isSatisfied(by: [1, 2, 3]))
    }

    enum Tenth: Refinement {
        static var constraints: [Constraint<Float>] {
            get throws(InvalidConstraint) { try [.minimum(-0.1), .maximum(0.1)] }
        }
    }

    @Test("A Float bound is stated as its description, 0.1 rather than the 0.10000000149011612 it widens to, by a constraint and a Refined type's keywords alike, and still checked as a Float")
    func floatBoundDescribed() throws {
        let expected: [ValidationKeyword] = [.minimum(-0.1), .maximum(0.1)]
        let sut = try Constraint<Float>.maximum(0.1)

        let actual = [try Constraint<Float>.minimum(-0.1).keyword, sut.keyword]

        #expect(actual == expected)
        #expect(ValidationKeyword.keywords(of: Refined<Float, Tenth>.self) == expected)
        #expect(sut.isSatisfied(by: 0.1))
        #expect(!sut.isSatisfied(by: Float(0.1).nextUp))
    }

    @Test("Each spelling's keyword is the JSON Schema keyword with its bound")
    func keywords() throws {
        let expected: [ValidationKeyword] = [
            .minLength(1), .maxLength(64), .pattern("^a$", example: "a"),
            .minimum(-3), .maximum(255), .minimum(0.25), .maximum(2.5),
            .minItems(0), .maxItems(9),
        ]

        let actual = [
            try Constraint<String>.minLength(1).keyword, try Constraint<String>.maxLength(64).keyword,
            try Constraint<String>.pattern("^a$", example: "a").keyword,
            try Constraint<Int8>.minimum(-3).keyword, try Constraint<UInt8>.maximum(255).keyword,
            try Constraint<Double>.minimum(0.25).keyword, try Constraint<Float>.maximum(2.5).keyword,
            try Constraint<[Int]>.minItems(0).keyword, try Constraint<[Int]>.maxItems(9).keyword,
        ]

        #expect(actual == expected)
    }

    @Test("Two constraints are equal when they check the same keyword", .tags(.conformance))
    func equality() throws {
        let first = try Constraint<String>.minLength(1)
        let same = try Constraint<String>.minLength(1)
        let other = try Constraint<String>.minLength(2)

        #expect(first == same)
        #expect(first.hashValue == same.hashValue)
        #expect(first != other)
    }

    @Test("A keyword describes itself as JSON Schema names it, a whole bound without a fraction")
    func descriptions() {
        let keywords: [ValidationKeyword] = [
            .minLength(1), .maxLength(2), .pattern("^a+$", example: "a"), .minimum(0), .maximum(2.5), .minItems(3), .maxItems(4), .minimum(1e20),
        ]
        let expected = ["minLength 1", "maxLength 2", "pattern ^a+$", "minimum 0", "maximum 2.5", "minItems 3", "maxItems 4", "minimum 1e+20"]

        let actual = keywords.map(\.description)

        #expect(actual == expected)
    }

    @Test("A violation describes the property and the keyword it breaks")
    func violationDescription() {
        let sut = ConstraintViolation(property: "query", keyword: .minLength(1))
        let expected = "\"query\" breaks minLength 1"

        let actual = sut.description

        #expect(actual == expected)
    }

    @Test("A violation of a constraint that couldn't be built names the property, the declaration and its error")
    func invalidConstraintViolation() {
        let sut = ConstraintViolation(property: "count", invalidConstraint: ".maximum(limit)", error: .inexactBound)
        let expectedCause = ConstraintViolation.Cause.invalidConstraint(declaration: ".maximum(limit)", error: .inexactBound)
        let expected = #""count"'s .maximum(limit) can't be built (inexactBound)"#

        let actual = sut.description

        #expect(actual == expected)
        #expect(sut.property == "count")
        #expect(sut.cause == expectedCause)
    }
}
