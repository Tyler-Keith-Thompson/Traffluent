import Events
import Testing

@Suite("Constraint")
struct ConstraintTests {
    @Test("minLength accepts a string of exactly its length and counts Unicode scalars, not characters")
    func minLength() {
        let sut = Constraint<String>.minLength(2)
        let combined = "e\u{301}"

        #expect(!sut.isSatisfied(by: ""))
        #expect(!sut.isSatisfied(by: "a"))
        #expect(sut.isSatisfied(by: "ab"))
        #expect(sut.isSatisfied(by: "abc"))
        #expect(sut.isSatisfied(by: combined))
    }

    @Test("minLength 0 accepts the empty string")
    func minLengthZero() {
        let sut = Constraint<String>.minLength(0)

        #expect(sut.isSatisfied(by: ""))
    }

    @Test("maxLength accepts a string of exactly its length and rejects one scalar more")
    func maxLength() {
        let sut = Constraint<String>.maxLength(2)
        let combined = "e\u{301}"
        let flag = "🇬🇧"

        #expect(sut.isSatisfied(by: ""))
        #expect(sut.isSatisfied(by: "ab"))
        #expect(!sut.isSatisfied(by: "abc"))
        #expect(sut.isSatisfied(by: combined))
        #expect(sut.isSatisfied(by: flag))
        #expect(!Constraint<String>.maxLength(1).isSatisfied(by: combined))
        #expect(!Constraint<String>.maxLength(0).isSatisfied(by: "a"))
    }

    @Test("A pattern matches anywhere in the string unless it is anchored")
    func pattern() {
        let unanchored = Constraint<String>.pattern("[0-9]+", example: "7")
        let anchored = Constraint<String>.pattern("^[A-Z]{3}$", example: "ABC")

        #expect(unanchored.isSatisfied(by: "abc123def"))
        #expect(!unanchored.isSatisfied(by: "abc"))
        #expect(anchored.isSatisfied(by: "XYZ"))
        #expect(!anchored.isSatisfied(by: "XYZW"))
        #expect(!anchored.isSatisfied(by: "xyz"))
        #expect(!anchored.isSatisfied(by: ""))
    }

    @Test("An integer's minimum and maximum include the bound itself")
    func integerBounds() {
        let minimum = Constraint<Int>.minimum(-2)
        let maximum = Constraint<UInt8>.maximum(10)

        #expect(!minimum.isSatisfied(by: -3))
        #expect(minimum.isSatisfied(by: -2))
        #expect(minimum.isSatisfied(by: .max))
        #expect(maximum.isSatisfied(by: 0))
        #expect(maximum.isSatisfied(by: 10))
        #expect(!maximum.isSatisfied(by: 11))
    }

    @Test("An integer bound compares in the integer's own type, exactly, past what a Double holds")
    func integerBoundExact() {
        let bound = Int64(9_007_199_254_740_993)
        let sut = Constraint<Int64>.minimum(bound)

        #expect(!sut.isSatisfied(by: bound - 1))
        #expect(sut.isSatisfied(by: bound))
    }

    @Test("A floating-point bound includes itself, and NaN satisfies no bound")
    func floatingPointBounds() {
        let minimum = Constraint<Double>.minimum(0.5)
        let maximum = Constraint<Float>.maximum(1)

        #expect(!minimum.isSatisfied(by: 0.49))
        #expect(minimum.isSatisfied(by: 0.5))
        #expect(!minimum.isSatisfied(by: .nan))
        #expect(maximum.isSatisfied(by: 1))
        #expect(!maximum.isSatisfied(by: 1.01))
        #expect(!maximum.isSatisfied(by: .nan))
    }

    @Test("minItems and maxItems count an array's elements, the bound included")
    func counts() {
        let minimum = Constraint<[String]>.minItems(1)
        let maximum = Constraint<[Int?]>.maxItems(2)

        #expect(!minimum.isSatisfied(by: []))
        #expect(minimum.isSatisfied(by: ["a"]))
        #expect(maximum.isSatisfied(by: [nil, nil]))
        #expect(!maximum.isSatisfied(by: [1, 2, 3]))
    }

    @Test("Each spelling's keyword is the JSON Schema keyword with its bound")
    func keywords() {
        let expected: [ValidationKeyword] = [
            .minLength(1), .maxLength(64), .pattern("^a$", example: "a"),
            .minimum(-3), .maximum(255), .minimum(0.25), .maximum(2.5),
            .minItems(0), .maxItems(9),
        ]

        let actual = [
            Constraint<String>.minLength(1).keyword, Constraint<String>.maxLength(64).keyword,
            Constraint<String>.pattern("^a$", example: "a").keyword,
            Constraint<Int8>.minimum(-3).keyword, Constraint<UInt8>.maximum(255).keyword,
            Constraint<Double>.minimum(0.25).keyword, Constraint<Float>.maximum(2.5).keyword,
            Constraint<[Int]>.minItems(0).keyword, Constraint<[Int]>.maxItems(9).keyword,
        ]

        #expect(actual == expected)
    }

    @Test("Two constraints are equal when they check the same keyword", .tags(.conformance))
    func equality() {
        let first = Constraint<String>.minLength(1)
        let same = Constraint<String>.minLength(1)
        let other = Constraint<String>.minLength(2)

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
}
