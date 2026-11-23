// How the check treats a property's constraint keywords: tightening one breaks the plan, loosening
// one leaves it out of date. Each test is self-contained.

import Events
import PropertyBased
import Testing
import TrackingPlans
import TraffluentTestSupport

@Suite("TrackingPlan: constraint check")
struct TrackingPlanConstraintCheckTests {
    @Test("Raising a lower bound, lowering an upper one, or adding one is breaking", arguments: [
        ([ValidationKeyword.minLength(1)], [ValidationKeyword.minLength(2)], "minLength", "1", "2"),
        ([.maxLength(9)], [.maxLength(8)], "maxLength", "9", "8"),
        ([.minimum(0)], [.minimum(0.5)], "minimum", "0", "0.5"),
        ([.maximum(10)], [.maximum(9)], "maximum", "10", "9"),
        ([.minItems(1)], [.minItems(3)], "minItems", "1", "3"),
        ([.maxItems(3)], [.maxItems(1)], "maxItems", "3", "1"),
    ])
    func tightened(committed: [ValidationKeyword], current: [ValidationKeyword], keyword: String, before: String, after: String) {
        let typeName = keyword.hasSuffix("Items") ? "[String]" : keyword.hasSuffix("Length") ? "String" : "Double"
        let committedPlan = TrackingPlan(schemas: [EventSchema(name: "searched", version: 1, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "query", typeName: typeName, isOptional: false, keywords: committed),
        ])])
        let sut = TrackingPlan(schemas: [EventSchema(name: "searched", version: 1, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "query", typeName: typeName, isOptional: false, keywords: current),
        ])])
        let expected = TrackingPlanCheck.breaking([
            .constraintTightened(event: "searched", version: 1, property: "query", keyword: keyword, committed: before, current: after),
        ])

        let actual = sut.check(against: committedPlan.files)

        #expect(actual == expected)
    }

    @Test("Lowering a lower bound, raising an upper one, or removing one only leaves the plan out of date", arguments: [
        ([ValidationKeyword.minLength(2)], [ValidationKeyword.minLength(1)], "minLength", "2" as String?, "1" as String?),
        ([.maxLength(8)], [], "maxLength", "8", nil),
        ([.minimum(-1)], [.minimum(-2.5)], "minimum", "-1", "-2.5"),
        ([.maximum(9)], [.maximum(10)], "maximum", "9", "10"),
        ([.minItems(3)], [], "minItems", "3", nil),
        ([.maxItems(1)], [.maxItems(3)], "maxItems", "1", "3"),
    ])
    func loosened(committed: [ValidationKeyword], current: [ValidationKeyword], keyword: String, before: String?, after: String?) {
        let typeName = keyword.hasSuffix("Items") ? "[String]" : keyword.hasSuffix("Length") ? "String" : "Double"
        let committedPlan = TrackingPlan(schemas: [EventSchema(name: "searched", version: 1, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "query", typeName: typeName, isOptional: false, keywords: committed),
        ])])
        let sut = TrackingPlan(schemas: [EventSchema(name: "searched", version: 1, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "query", typeName: typeName, isOptional: false, keywords: current),
        ])])
        let expected = TrackingPlanCheck.outOfDate([
            .constraintLoosened(event: "searched", version: 1, property: "query", keyword: keyword, committed: before, current: after),
        ])

        let actual = sut.check(against: committedPlan.files)

        #expect(actual == expected)
    }

    @Test("A pattern added or changed is breaking, one removed only out of date, and a changed example alone leaves the file out of date")
    func patterns() {
        func plan(_ keywords: [ValidationKeyword]) -> TrackingPlan {
            TrackingPlan(schemas: [EventSchema(name: "applied", version: 1, consentCategory: .analytics, properties: [
                EventSchema.Property(name: "code", typeName: "String", isOptional: false, keywords: keywords),
            ])])
        }
        let first = ValidationKeyword.pattern("^[A-Z]+$", example: "A")
        let second = ValidationKeyword.pattern("^.{6}$", example: "SPRING")
        let expectedAdded = TrackingPlanCheck.breaking([
            .constraintTightened(event: "applied", version: 1, property: "code", keyword: "pattern", committed: nil, current: #""^[A-Z]+$""#),
        ])
        let expectedChanged = TrackingPlanCheck.breaking([
            .constraintTightened(event: "applied", version: 1, property: "code", keyword: "pattern", committed: #""^[A-Z]+$""#, current: #""^.{6}$""#),
        ])
        let expectedRemoved = TrackingPlanCheck.outOfDate([
            .constraintLoosened(event: "applied", version: 1, property: "code", keyword: "pattern", committed: #"["^[A-Z]+$", "^.{6}$"]"#, current: #""^.{6}$""#),
        ])
        let expectedExample = TrackingPlanCheck.outOfDate([.fileOutOfDate(path: "applied.v1.example.json"), .fileOutOfDate(path: "applied.v1.schema.json")])

        let added = plan([first]).check(against: plan([]).files)
        let changed = plan([second]).check(against: plan([first]).files)
        let removed = plan([second]).check(against: plan([first, second]).files)
        let example = plan([.pattern("^[A-Z]+$", example: "B")]).check(against: plan([first]).files)

        #expect(added == expectedAdded)
        #expect(changed == expectedChanged)
        #expect(removed == expectedRemoved)
        #expect(example == expectedExample)
    }

    @Test("A retyped property reports the retyping alone, not its bounds")
    func retypedHidesBounds() {
        let committed = TrackingPlan(schemas: [EventSchema(name: "searched", version: 1, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "count", typeName: "UInt8", isOptional: false),
        ])])
        let sut = TrackingPlan(schemas: [EventSchema(name: "searched", version: 1, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "count", typeName: "String", isOptional: false, keywords: [.minLength(1)]),
        ])])
        let expected = TrackingPlanCheck.breaking([
            .propertyRetyped(event: "searched", version: 1, property: "count", committed: #"{"type": "integer"}"#, current: #"{"type": "string"}"#),
        ])

        let actual = sut.check(against: committed.files)

        #expect(actual == expected)
    }

    @Test("Widening an integer type loosens its bounds, and narrowing one tightens them")
    func integerWidths() {
        func plan(_ typeName: String) -> TrackingPlan {
            TrackingPlan(schemas: [EventSchema(name: "searched", version: 1, consentCategory: .analytics, properties: [
                EventSchema.Property(name: "count", typeName: typeName, isOptional: false),
            ])])
        }
        let expectedWidened = TrackingPlanCheck.outOfDate([
            .constraintLoosened(event: "searched", version: 1, property: "count", keyword: "maximum", committed: "255", current: "65535"),
        ])
        let expectedNarrowed = TrackingPlanCheck.breaking([
            .constraintTightened(event: "searched", version: 1, property: "count", keyword: "minimum", committed: nil, current: "0"),
            .constraintTightened(event: "searched", version: 1, property: "count", keyword: "maximum", committed: nil, current: "255"),
        ])

        let widened = plan("UInt16").check(against: plan("UInt8").files)
        let narrowed = plan("UInt8").check(against: plan("Int").files)

        #expect(widened == expectedWidened)
        #expect(narrowed == expectedNarrowed)
    }

    @Test("A constraint difference describes the keyword gained, lost or changed, and whether it is tighter")
    func descriptions() {
        let differences: [TrackingPlanDifference] = [
            .constraintTightened(event: "searched", version: 2, property: "query", keyword: "minLength", committed: nil, current: "1"),
            .constraintTightened(event: "searched", version: 2, property: "query", keyword: "maxLength", committed: "9", current: "8"),
            .constraintLoosened(event: "searched", version: 2, property: "query", keyword: "minimum", committed: "0", current: nil),
        ]
        let expected = [
            #"searched v2: property "query" gained minLength 1, which is tighter"#,
            #"searched v2: property "query" changed maxLength from 9 to 8, which is tighter"#,
            #"searched v2: property "query" lost minimum 0, which is looser"#,
        ]

        let actual = differences.map(\.description)

        #expect(actual == expected)
        #expect(differences.map(\.isBreaking) == [true, true, false])
    }

    @Test("Any change to one bound is tightened exactly when a naive comparison says the bound narrowed", .tags(.randomized))
    func anyBound() async {
        let keywords = ["minLength", "maxLength", "minItems", "maxItems", "minimum", "maximum"]
        await propertyCheck(count: 300, input: Gen.int(in: 0 ... 5), Gen.int(in: -1 ... 6), Gen.int(in: -1 ... 6)) { kind, before, after in
            let name = keywords[kind]
            let isLower = name.hasPrefix("min")
            func keyword(_ value: Int) -> [ValidationKeyword] {
                guard value >= 0 else { return [] }
                return switch name {
                case "minLength": [.minLength(value)]
                case "maxLength": [.maxLength(value)]
                case "minItems": [.minItems(value)]
                case "maxItems": [.maxItems(value)]
                case "minimum": [.minimum(Double(value))]
                default: [.maximum(Double(value))]
                }
            }
            func plan(_ value: Int) -> TrackingPlan {
                TrackingPlan(schemas: [EventSchema(name: "e", version: 1, consentCategory: .analytics, properties: [
                    EventSchema.Property(name: "p", typeName: name.hasSuffix("Items") ? "[Int]" : name.hasSuffix("Length") ? "String" : "Double", isOptional: false, keywords: keyword(value)),
                ])])
            }
            // -1 is no bound: the loosest of all.
            let expectedTightened: Bool? = before == after ? nil
                : before < 0 ? true
                : after < 0 ? false
                : isLower ? after > before : after < before

            let actual = plan(after).check(against: plan(before).files).differences.first

            switch (expectedTightened, actual) {
            case (nil, nil): break
            case (true?, .constraintTightened?): break
            case (false?, .constraintLoosened?): break
            default: Issue.record("\(name) \(before) to \(after): \(String(describing: actual))")
            }
        }
    }
}
